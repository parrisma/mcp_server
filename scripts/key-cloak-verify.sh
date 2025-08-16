#!/bin/bash

# Configurable variables
KEYCLOAK_URL="http://localhost:8081"
REALM="openwebui"
ADMIN_USER="admin"
ADMIN_PASS="password"
CLIENT_ID_TO_CHECK="open-webui" # Primary client ID (used for existence + default ROPC)
USER_TO_CHECK="test"
USER_PASSWORD="password" # Password to verify via resource owner password credentials flow
ROPC_CLIENT_ID="${ROPC_CLIENT_ID:-$CLIENT_ID_TO_CHECK}" # ROPC client (defaults to CLIENT_ID_TO_CHECK unless overridden)
ROPC_CLIENT_SECRET="${ROPC_CLIENT_SECRET:-}" # Optional: set if confidential client requires secret; auto-fetched if empty
SKIP_PASSWORD_VERIFY=${SKIP_PASSWORD_VERIFY:-0}
AUTO_CLEAR_REQUIRED_ACTIONS=${AUTO_CLEAR_REQUIRED_ACTIONS:-0} # If 1, will remove requiredActions and mark emailVerified true

# Optional: total seconds to wait for Keycloak to become available
WAIT_FOR_KEYCLOAK_TIMEOUT=${WAIT_FOR_KEYCLOAK_TIMEOUT:-60}
WAIT_FOR_KEYCLOAK_INTERVAL=${WAIT_FOR_KEYCLOAK_INTERVAL:-3}

# Tab prefix for formatted output
TAB=$'\t'

echo "Checking Keycloak availability at $KEYCLOAK_URL (timeout ${WAIT_FOR_KEYCLOAK_TIMEOUT}s)..."
START_TIME=$(date +%s)
while true; do
  # We try a realm endpoint first (more specific) then fallback to root
  STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$KEYCLOAK_URL/realms/master")
  if [[ "$STATUS_CODE" == "200" ]]; then
  printf "%sKeycloak is up (master realm reachable).\n" "$TAB"
    break
  fi
  ROOT_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$KEYCLOAK_URL")
  if [[ "$ROOT_STATUS" =~ ^(200|302)$ ]]; then
  printf "%sKeycloak is up (root endpoint status %s).\n" "$TAB" "$ROOT_STATUS"
    break
  fi
  NOW=$(date +%s)
  ELAPSED=$(( NOW - START_TIME ))
  if (( ELAPSED >= WAIT_FOR_KEYCLOAK_TIMEOUT )); then
  printf "%sERROR: Keycloak not reachable at %s within %ss (last /realms/master status %s, root %s).\n" "$TAB" "$KEYCLOAK_URL" "$WAIT_FOR_KEYCLOAK_TIMEOUT" "$STATUS_CODE" "$ROOT_STATUS" >&2
    exit 1
  fi
  echo "Waiting... (elapsed ${ELAPSED}s, /realms/master:$STATUS_CODE root:$ROOT_STATUS)"
  sleep "$WAIT_FOR_KEYCLOAK_INTERVAL"
done

echo "Continuing with verification steps..."

# Warn if client IDs differ
if [ "$CLIENT_ID_TO_CHECK" != "$ROPC_CLIENT_ID" ]; then
  printf "%sNOTICE: CLIENT_ID_TO_CHECK (%s) differs from ROPC_CLIENT_ID (%s); ensure both exist and ROPC has Direct Access Grants enabled.\n" "$TAB" "$CLIENT_ID_TO_CHECK" "$ROPC_CLIENT_ID"
fi

# Step 1: Get admin access token
printf "%sRequesting admin access token...\n" "$TAB"
TOKEN_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASS" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
  printf "%sFailed to retrieve access token. Response:\n" "$TAB"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

printf "%sAccess token retrieved.\n" "$TAB"

# Step 1.5: Verify realm exists
printf "%sVerifying realm '%s' exists...\n" "$TAB" "$REALM"
REALM_RESPONSE=$(curl -s -o /dev/null -w '%{http_code}' "$KEYCLOAK_URL/admin/realms/$REALM" -H "Authorization: Bearer $ACCESS_TOKEN")
if [ "$REALM_RESPONSE" != "200" ]; then
  printf "%sERROR: Realm '%s' not found (HTTP %s).\n" "$TAB" "$REALM" "$REALM_RESPONSE" >&2
  echo "Available realms:" >&2
  curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KEYCLOAK_URL/admin/realms" | jq -r '.[].realm' >&2
  exit 2
fi
printf "%sRealm '%s' exists.\n" "$TAB" "$REALM"

# Step 2: Query clients in the realm
printf "Checking for client '%s' in realm '%s'...\n" "$CLIENT_ID_TO_CHECK" "$REALM"
CLIENTS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

# Step 3: Search for the client
MATCH=$(echo "$CLIENTS" | jq -r --arg cid "$CLIENT_ID_TO_CHECK" '.[] | select(.clientId == $cid)')

if [ -n "$MATCH" ]; then
  printf "%sClient '%s' exists:\n" "$TAB" "$CLIENT_ID_TO_CHECK"
  #echo "$MATCH" | jq
else
  printf "%sClient '%s' not found in realm '%s'.\n" "$TAB" "$CLIENT_ID_TO_CHECK" "$REALM"
fi

# Step 4: Check user existence
printf "Checking for user '%s' in realm '%s'...\n" "$USER_TO_CHECK" "$REALM"
USERS_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KEYCLOAK_URL/admin/realms/$REALM/users?username=$USER_TO_CHECK")
FOUND_USERNAME=$(echo "$USERS_JSON" | jq -r '.[0].username // empty')
if [ "$FOUND_USERNAME" = "$USER_TO_CHECK" ]; then
  printf "%sUser '%s' exists.\n" "$TAB" "$USER_TO_CHECK"
else
  printf "%sUser '%s' NOT found in realm '%s'.\n" "$TAB" "$USER_TO_CHECK" "$REALM"
  # Don't attempt password verification if user missing
  SKIP_PASSWORD_VERIFY=1
fi

# Step 4.1: Inspect full user details & required actions (may block ROPC)
if [ "$SKIP_PASSWORD_VERIFY" = "0" ]; then
  USER_ID=$(echo "$USERS_JSON" | jq -r '.[0].id // empty')
  if [ -n "$USER_ID" ]; then
    FULL_USER_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID")
    REQUIRED_ACTIONS=$(echo "$FULL_USER_JSON" | jq -r '.requiredActions | join(",")')
    ENABLED_FLAG=$(echo "$FULL_USER_JSON" | jq -r '.enabled')
    EMAIL_VERIFIED=$(echo "$FULL_USER_JSON" | jq -r '.emailVerified')
    printf "%sUser details: enabled=%s emailVerified=%s requiredActions=%s\n" "$TAB" "$ENABLED_FLAG" "$EMAIL_VERIFIED" "${REQUIRED_ACTIONS:-<none>}"
    if [ -n "$REQUIRED_ACTIONS" ]; then
      printf "%sWARNING: Required actions present; password grant may fail with 'Account is not fully set up'.\n" "$TAB"
      if [ "$AUTO_CLEAR_REQUIRED_ACTIONS" = "1" ]; then
        printf "%sAttempting to clear requiredActions & set emailVerified=true (AUTO_CLEAR_REQUIRED_ACTIONS=1).\n" "$TAB"
        UPDATED_USER_JSON=$(echo "$FULL_USER_JSON" | jq '.requiredActions=[] | .emailVerified=true')
        UPDATE_RESP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$UPDATED_USER_JSON" \
          "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID")
        if [ "$UPDATE_RESP_CODE" = "204" ]; then
          printf "%sCleared required actions successfully.\n" "$TAB"
          # Reload to confirm
          FULL_USER_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID")
          REQUIRED_ACTIONS=$(echo "$FULL_USER_JSON" | jq -r '.requiredActions | join(",")')
          EMAIL_VERIFIED=$(echo "$FULL_USER_JSON" | jq -r '.emailVerified')
          printf "%sPost-update user details: emailVerified=%s requiredActions=%s\n" "$TAB" "$EMAIL_VERIFIED" "${REQUIRED_ACTIONS:-<none>}"
        else
          printf "%sERROR: Failed to update user (HTTP %s).\n" "$TAB" "$UPDATE_RESP_CODE"
        fi
      else
        printf "%s(Set AUTO_CLEAR_REQUIRED_ACTIONS=1 to auto-clear for dev environments.)\n" "$TAB"
      fi
    fi
  fi
fi

  # Step 4.5: Inspect ROPC client configuration
  if [ "$SKIP_PASSWORD_VERIFY" = "0" ]; then
    printf "%sInspecting ROPC client '%s' for password grant suitability...\n" "$TAB" "$ROPC_CLIENT_ID"
    ROPC_CLIENT_JSON=$(echo "$CLIENTS" | jq -r --arg cid "$ROPC_CLIENT_ID" '.[] | select(.clientId == $cid)')
    if [ -z "$ROPC_CLIENT_JSON" ]; then
      printf "%sERROR: ROPC client '%s' not found in realm '%s'. Cannot verify password.\n" "$TAB" "$ROPC_CLIENT_ID" "$REALM"
      SKIP_PASSWORD_VERIFY=1
    else
      ROPC_INTERNAL_ID=$(echo "$ROPC_CLIENT_JSON" | jq -r '.id')
      ROPC_PUBLIC=$(echo "$ROPC_CLIENT_JSON" | jq -r '.publicClient')
      ROPC_DAG=$(echo "$ROPC_CLIENT_JSON" | jq -r '.directAccessGrantsEnabled')
      ROPC_CONF=$(echo "$ROPC_CLIENT_JSON" | jq -r '.clientAuthenticatorType')
      printf "%sClient details: publicClient=%s directAccessGrantsEnabled=%s authenticatorType=%s internalId=%s\n" "$TAB" "$ROPC_PUBLIC" "$ROPC_DAG" "$ROPC_CONF" "$ROPC_INTERNAL_ID"
      if [ "$ROPC_DAG" != "true" ]; then
        printf "%sWARNING: directAccessGrantsEnabled=false. Enable 'Direct Access Grants' for client '%s' in Keycloak UI.\n" "$TAB" "$ROPC_CLIENT_ID"
      fi
      if [ "$ROPC_PUBLIC" = "false" ]; then
        # Confidential client likely needs a secret unless set to other auth types
        if [ -z "$ROPC_CLIENT_SECRET" ]; then
          printf "%sAttempting to fetch client secret (confidential client)...\n" "$TAB"
          CLIENT_SECRET_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KEYCLOAK_URL/admin/realms/$REALM/clients/$ROPC_INTERNAL_ID/client-secret")
          ROPC_CLIENT_SECRET=$(echo "$CLIENT_SECRET_RESPONSE" | jq -r '.value // empty')
          if [ -n "$ROPC_CLIENT_SECRET" ]; then
            printf "%sFetched client secret length=%s\n" "$TAB" "${#ROPC_CLIENT_SECRET}" | sed 's/./*/g'
          else
            printf "%sWARNING: Could not retrieve client secret; password grant may fail.\n" "$TAB"
          fi
        else
          printf "%sUsing provided ROPC_CLIENT_SECRET (length %s).\n" "$TAB" "${#ROPC_CLIENT_SECRET}"
        fi
      else
        if [ -n "$ROPC_CLIENT_SECRET" ]; then
          printf "%sNOTE: Public client provided a secret; it will be ignored.\n" "$TAB"
        fi
      fi
    fi
  fi

# Step 5: Verify user password (optional)
if [ "$SKIP_PASSWORD_VERIFY" = "0" ]; then
  printf "%sVerifying password for user '%s' using client '%s'...\n" "$TAB" "$USER_TO_CHECK" "$ROPC_CLIENT_ID"
    TOKEN_POST_DATA=(
      "username=$USER_TO_CHECK"
      "password=$USER_PASSWORD"
      "grant_type=password"
      "client_id=$ROPC_CLIENT_ID"
    )
    if [ -n "$ROPC_CLIENT_SECRET" ]; then
      TOKEN_POST_DATA+=("client_secret=$ROPC_CLIENT_SECRET")
    fi
    # Join form data
    FORM_STRING=$(IFS='&'; echo "${TOKEN_POST_DATA[*]}")
    USER_TOKEN_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "$FORM_STRING")
  USER_ACCESS_TOKEN=$(echo "$USER_TOKEN_RESPONSE" | jq -r '.access_token // empty')
  if [ -n "$USER_ACCESS_TOKEN" ]; then
    printf "%sPassword verification SUCCESS for user '%s'.\n" "$TAB" "$USER_TO_CHECK"
  else
    ERROR_DESC=$(echo "$USER_TOKEN_RESPONSE" | jq -r '.error_description // .error // "unknown_error"')
    printf "%sPassword verification FAILED for user '%s' (reason: %s).\n" "$TAB" "$USER_TO_CHECK" "$ERROR_DESC"
    # Optionally output full response for debugging
    printf "%sFull response: %s\n" "$TAB" "$USER_TOKEN_RESPONSE"
  fi
else
  printf "%sSkipping password verification. (Set SKIP_PASSWORD_VERIFY=0 to enable)\n" "$TAB"
fi