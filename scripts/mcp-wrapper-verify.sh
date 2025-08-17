#!/usr/bin/env bash
# Verify the MCP adapter health endpoint.
# Succeeds (exit 0) only if the /health endpoint returns JSON with .status == expected (default 'ok').
# Fails with distinct exit codes otherwise.
#
# Environment / CLI overrides:
#   MCP_WRAPPER_HEALTH_URL / --url           Health endpoint URL (default http://localhost:8088/health)
#   MCP_WRAPPER_EXPECT_STATUS                Expected top-level .status (default ok)
#   LITELLM_API_KEY                          Bearer token for tool calls (REQUIRED for tool verification)
#   MCP_WRAPPER_TOOL_BASE_URL                Base URL for tool calls (default http://localhost:8088/mcp-rest/tools/call)
#   MCP_WRAPPER_KV_KEY                       Key to store (default name)
#   MCP_WRAPPER_KV_VALUE                     Value to store (default Bobby123)
#   MCP_WRAPPER_KV_GROUP                     Group name (default people)
#   MCP_WRAPPER_SKIP_TOOLS=1                 Skip put/get tool verification
#   (Other prior structure checks removed for minimal mode)
#   MCP_WRAPPER_TIMEOUT                      Curl max time in seconds (default 5)
#   MCP_WRAPPER_RETRIES                      Retries (default 5)
#   MCP_WRAPPER_RETRY_DELAY                  Seconds between retries (default 2)
#   MCP_WRAPPER_VERBOSE=1                    Verbose logging
#
# Exit Codes:
#   0 success
#   1 network/HTTP failure (non-2xx or curl error)
#   2 invalid JSON / parse error
#   3 status mismatch
#   6 tool call failure (HTTP / JSON)
#   7 value mismatch
#   4 dependency missing (curl/jq)
#   5 usage error

set -euo pipefail

log() { echo "[mcp-wrapper-verify] $*"; }
verbose() { [[ ${VERBOSE:-0} -eq 1 ]] && log "$*" || true; }

# Parse simple CLI flags
URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 5 ;;
  esac
done

# Defaults
URL="${URL:-${MCP_WRAPPER_HEALTH_URL:-http://localhost:8088/health}}"
EXPECT_STATUS="${MCP_WRAPPER_EXPECT_STATUS:-ok}"
TIMEOUT="${MCP_WRAPPER_TIMEOUT:-5}"
RETRIES="${MCP_WRAPPER_RETRIES:-5}"
RETRY_DELAY="${MCP_WRAPPER_RETRY_DELAY:-2}"
TOOL_BASE_URL="${MCP_WRAPPER_TOOL_BASE_URL:-http://localhost:8088/mcp-rest/tools/call}"
KV_KEY="${MCP_WRAPPER_KV_KEY:-name}"
KV_VALUE="${MCP_WRAPPER_KV_VALUE:-Bobby123}"
KV_GROUP="${MCP_WRAPPER_KV_GROUP:-people}"
SKIP_TOOLS="${MCP_WRAPPER_SKIP_TOOLS:-0}"
VERBOSE="${MCP_WRAPPER_VERBOSE:-${VERBOSE:-0}}"

# Dependencies
for dep in curl jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "ERROR: missing dependency: $dep" >&2; exit 4
  fi
done

verbose "URL=$URL EXPECT_STATUS=$EXPECT_STATUS TOOL_BASE_URL=$TOOL_BASE_URL KEY=$KV_KEY GROUP=$KV_GROUP" 

attempt=0
resp_file="$(mktemp)"
http_code=""
trap 'rm -f "$resp_file"' EXIT

while (( attempt < RETRIES )); do
  attempt=$((attempt+1))
  verbose "Attempt $attempt/$RETRIES"
  if ! http_code=$(curl -sS -w '%{http_code}' -m "$TIMEOUT" -o "$resp_file" "$URL" || true); then
    http_code=""
  fi
  if [[ -z "$http_code" ]]; then
    verbose "No HTTP code (curl error)."
  elif [[ "$http_code" =~ ^2 ]]; then
    break
  else
    verbose "HTTP $http_code";
  fi
  if (( attempt < RETRIES )); then sleep "$RETRY_DELAY"; fi
done

if [[ -z "$http_code" ]]; then
  echo "ERROR: request failed (curl error)" >&2; exit 1
fi
if [[ ! "$http_code" =~ ^2 ]]; then
  echo "ERROR: unexpected HTTP status $http_code" >&2; exit 1
fi

# Validate JSON
if ! jq -e . >/dev/null 2>&1 < "$resp_file"; then
  echo "ERROR: invalid JSON returned" >&2; verbose "Body: $(cat "$resp_file")"; exit 2
fi

status_val=$(jq -r '.status // empty' < "$resp_file")
if [[ -z "$status_val" ]]; then
  echo "ERROR: missing status field" >&2; exit 3
fi
if [[ "$status_val" != "$EXPECT_STATUS" ]]; then
  echo "ERROR: status mismatch (got '$status_val', expected '$EXPECT_STATUS')" >&2; exit 3
fi

# Optional: chrono sanity (date & timestamp ISO) - soft warning only
if jq -e '.date and .timestamp' >/dev/null 2>&1 < "$resp_file"; then
  verbose "Date fields present: $(jq -r '.date, .timestamp' < "$resp_file" | paste -sd ' / ')"
else
  verbose "Date/timestamp fields missing (non-fatal)"
fi

echo "status=$status_val OK"

if [[ "$SKIP_TOOLS" == "1" ]]; then
  verbose "Skipping tool verification per MCP_WRAPPER_SKIP_TOOLS"
  exit 0
fi

if [[ -z "${LITELLM_API_KEY:-}" ]]; then
  echo "ERROR: LITELLM_API_KEY not set (required for tool verification)" >&2; exit 5
fi

auth_header=( -H "Authorization: Bearer $LITELLM_API_KEY" )
common_headers=( -H "Content-Type: application/json" )

put_payload=$(jq -n --arg k "$KV_KEY" --arg v "$KV_VALUE" --arg g "$KV_GROUP" '{arguments:{key:$k,value:$v,group:$g}}')
get_payload=$(jq -n --arg k "$KV_KEY" --arg g "$KV_GROUP" '{arguments:{key:$k,group:$g}}')

put_url="${TOOL_BASE_URL%/}/secure_datagroup-put_key_value"
get_url="${TOOL_BASE_URL%/}/secure_datagroup-get_value_by_key"

verbose "PUT call -> $put_url"
put_resp_file=$(mktemp)
trap 'rm -f "$put_resp_file" "$get_resp_file"' EXIT
put_code=$(curl -sS -w '%{http_code}' -m "$TIMEOUT" -o "$put_resp_file" "${auth_header[@]}" "${common_headers[@]}" -X POST "$put_url" -d "$put_payload" || true)
if [[ ! $put_code =~ ^2 ]]; then
  echo "ERROR: put_key_value HTTP $put_code" >&2; verbose "Body: $(cat "$put_resp_file")"; exit 6
fi

# Try to parse put response for quick validation (non-fatal if JSON invalid)
if jq -e . >/dev/null 2>&1 < "$put_resp_file"; then
  put_status=$(jq -r '.status? // empty' < "$put_resp_file")
  verbose "put response status=$put_status"
fi

sleep 0.5
verbose "GET call -> $get_url"
get_resp_file=$(mktemp)
get_code=$(curl -sS -w '%{http_code}' -m "$TIMEOUT" -o "$get_resp_file" "${auth_header[@]}" "${common_headers[@]}" -X POST "$get_url" -d "$get_payload" || true)
if [[ ! $get_code =~ ^2 ]]; then
  echo "ERROR: get_value_by_key HTTP $get_code" >&2; verbose "Body: $(cat "$get_resp_file")"; exit 6
fi

if ! jq -e . >/dev/null 2>&1 < "$get_resp_file"; then
  echo "ERROR: get response not JSON" >&2; exit 6
fi

# Extract value robustly across possible response shapes (object, array, embedded JSON in text fields)
verbose "Raw get response: $(head -c 500 "$get_resp_file")"

retrieved_value=""

# 1. Direct object with value
retrieved_value=$(jq -r 'if type=="object" and has("value") then .value else empty end' < "$get_resp_file" 2>/dev/null || true)

# 2. Object with content array -> text containing JSON
if [[ -z "$retrieved_value" ]]; then
  embedded_texts=$(jq -r 'if type=="object" and has("content") then [.content[]? | .text? // empty][] else empty end' < "$get_resp_file" 2>/dev/null || true)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == \{* || "$line" == \[* ]]; then
      val=$(printf '%s' "$line" | jq -r 'try (.. | objects | select(has("value")) | .value) catch empty' 2>/dev/null || true)
      if [[ -n "$val" ]]; then retrieved_value="$val"; break; fi
    fi
  done <<< "$embedded_texts"
fi

# 3. Root array of objects each with potential value
if [[ -z "$retrieved_value" ]]; then
  retrieved_value=$(jq -r 'if type=="array" then (.[].value? // empty) else empty end' < "$get_resp_file" 2>/dev/null | head -n1 || true)
fi

# 4. Root array where elements have text field containing JSON string with value
if [[ -z "$retrieved_value" ]]; then
  mapfile -t array_texts < <(jq -r 'if type=="array" then [.[] | .text? // empty][] else empty end' < "$get_resp_file" 2>/dev/null || true)
  for t in "${array_texts[@]}"; do
    [[ -z "$t" ]] && continue
    if [[ "$t" == \{* || "$t" == \[* ]]; then
      val=$(printf '%s' "$t" | jq -r 'try (.. | objects | select(has("value")) | .value) catch empty' 2>/dev/null || true)
      if [[ -n "$val" ]]; then retrieved_value="$val"; break; fi
    fi
  done
fi

if [[ -z "$retrieved_value" ]]; then
  echo "ERROR: could not extract value from get response" >&2; verbose "Body: $(cat "$get_resp_file")"; exit 6
fi

if [[ "$retrieved_value" != "$KV_VALUE" ]]; then
  echo "ERROR: value mismatch (got '$retrieved_value', expected '$KV_VALUE')" >&2; exit 7
fi

echo "tool round-trip OK key=$KV_KEY value=$retrieved_value"
exit 0
