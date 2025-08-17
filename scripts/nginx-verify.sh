#!/usr/bin/env bash
# nginx-verify.sh
# Verify the nginx-mcp service is reachable on the expected port, then (optionally)
# perform an MCP tool round-trip (put_key_value / get_value_by_key) through the
# nginx-exposed /mcp-rest/tools/call interface, asserting the stored value matches.
# Defaults assume the stack port mapping "9000:80" (host port 9000).
#
# Environment overrides:
#   NGINX_HOST        (default: localhost)
#   NGINX_PORT        (default: 9000)
#   NGINX_URL         (full URL override; if set, host/port ignored)
#   MAX_RETRIES       (default: 20)
#   SLEEP_SECONDS     (default: 3)
#   EXPECT_STATUS     (space separated list of acceptable HTTP codes; default: "200 301 302")
#   EXTRA_PATH        (extra path to try after root, e.g. /mcp/ )
#
# MCP round-trip verification (all optional; if neither MCP_API_KEY nor LITELLM_API_KEY set, skip round-trip):
#   MCP_API_KEY            Bearer token required to call tools (primary variable)
#   LITELLM_API_KEY        Fallback token (used if MCP_API_KEY unset)
#   MCP_PUT_TOOL           (default: secure_datagroup-put_key_value)
#   MCP_GET_TOOL           (default: secure_datagroup-get_value_by_key)
#   MCP_KEY                (default: name)
#   MCP_VALUE              (default: auto-random Value-<RANDOM>)
#   MCP_GROUP              (default: people)
#   MCP_CALL_BASE          (default: http://<host>:<port>/mcp-rest/tools/call)
#   MCP_RETRIES            (default: 5) retry attempts for each tool call on transport errors
#   MCP_SLEEP_SECONDS      (default: 2) sleep between retries
#   MCP_EXPECT_STATUS      (default: 200) expected HTTP status for tool calls
#
# Exit codes:
#   0 success
#   1 dependency missing (curl or jq if used later)
#   2 connection / status never became healthy
#   3 unexpected runtime error
#
set -euo pipefail

NGINX_HOST=${NGINX_HOST:-localhost}
NGINX_PORT=${NGINX_PORT:-9000}
MAX_RETRIES=${MAX_RETRIES:-20}
SLEEP_SECONDS=${SLEEP_SECONDS:-3}
EXPECT_STATUS=${EXPECT_STATUS:-"200 301 302"}
EXTRA_PATH=${EXTRA_PATH:-}

if [[ -n "${NGINX_URL:-}" ]]; then
  BASE_URL="$NGINX_URL"
else
  BASE_URL="http://${NGINX_HOST}:${NGINX_PORT}"
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required" >&2
  exit 1
fi

# Fallback: use LITELLM_API_KEY if MCP_API_KEY not provided
if [[ -z "${MCP_API_KEY:-}" && -n "${LITELLM_API_KEY:-}" ]]; then
  MCP_API_KEY="$LITELLM_API_KEY"
fi

# jq required only if doing MCP validation (parsing response)
if [[ -n "${MCP_API_KEY:-}" ]] && ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for MCP round-trip but not found" >&2
  exit 1
fi

accept_status() {
  local code=$1
  for s in $EXPECT_STATUS; do
    if [[ "$s" == "$code" ]]; then
      return 0
    fi
  done
  return 1
}

attempt=0
status_code=""
while (( attempt < MAX_RETRIES )); do
  attempt=$(( attempt + 1 ))
  status_code=$(curl -ksS -o /dev/null -w '%{http_code}' "${BASE_URL}/" || true)
  if accept_status "$status_code"; then
    echo "INFO: nginx responded with acceptable status $status_code on attempt $attempt"
    root_ok=true
    break
  fi
  echo "WARN: attempt $attempt/${MAX_RETRIES} got status '$status_code' (wanted one of: $EXPECT_STATUS); retrying in ${SLEEP_SECONDS}s" >&2
  sleep "$SLEEP_SECONDS"
  root_ok=false
done

if [[ "$root_ok" != true ]]; then
  echo "ERROR: nginx never returned an acceptable status after $MAX_RETRIES attempts (last: $status_code)" >&2
  exit 2
fi

# Optional extra path test
if [[ -n "$EXTRA_PATH" ]]; then
  # ensure leading slash
  if [[ "$EXTRA_PATH" != /* ]]; then
    EXTRA_PATH="/$EXTRA_PATH"
  fi
  status_code_extra=$(curl -ksS -o /dev/null -w '%{http_code}' "${BASE_URL}${EXTRA_PATH}" || true)
  if accept_status "$status_code_extra"; then
    echo "INFO: nginx extra path ${EXTRA_PATH} responded with $status_code_extra"
  else
    echo "WARN: nginx extra path ${EXTRA_PATH} responded with $status_code_extra (ignored)" >&2
  fi
fi

echo "SUCCESS: nginx verification passed (${BASE_URL})"

# ---------------- MCP tool round-trip (optional) ----------------
if [[ -z "${MCP_API_KEY:-}" ]]; then
  echo "INFO: No MCP_API_KEY (or LITELLM_API_KEY) provided; skipping MCP tool round-trip test." >&2
  exit 0
fi

MCP_PUT_TOOL=${MCP_PUT_TOOL:-secure_datagroup-put_key_value}
MCP_GET_TOOL=${MCP_GET_TOOL:-secure_datagroup-get_value_by_key}
MCP_KEY=${MCP_KEY:-name}
MCP_VALUE=${MCP_VALUE:-Value-${RANDOM}}
MCP_GROUP=${MCP_GROUP:-people}
MCP_CALL_BASE=${MCP_CALL_BASE:-${BASE_URL}/mcp-rest/tools/call}
MCP_RETRIES=${MCP_RETRIES:-5}
MCP_SLEEP_SECONDS=${MCP_SLEEP_SECONDS:-2}
MCP_EXPECT_STATUS=${MCP_EXPECT_STATUS:-200}

call_tool() {
  local tool=$1
  local payload=$2
  local attempt=0
  local http_code
  local response_file
  response_file=$(mktemp)
  while (( attempt < MCP_RETRIES )); do
    attempt=$(( attempt + 1 ))
    http_code=$(curl -sS -o "$response_file" -w '%{http_code}' -X POST \
      -H "Authorization: Bearer ${MCP_API_KEY}" \
      -H 'Content-Type: application/json' \
      "${MCP_CALL_BASE}/${tool}" \
      -d "$payload" || echo "000")
    if [[ "$http_code" == "$MCP_EXPECT_STATUS" ]]; then
      cat "$response_file"
      rm -f "$response_file"
      return 0
    fi
    echo "WARN: tool $tool attempt $attempt/$MCP_RETRIES got HTTP $http_code (want $MCP_EXPECT_STATUS); retrying in $MCP_SLEEP_SECONDS s" >&2
    sleep "$MCP_SLEEP_SECONDS"
  done
  echo "ERROR: tool $tool failed after $MCP_RETRIES attempts (last HTTP $http_code)" >&2
  cat "$response_file" >&2 || true
  rm -f "$response_file"
  return 1
}

put_payload=$(jq -nc --arg key "$MCP_KEY" --arg val "$MCP_VALUE" --arg grp "$MCP_GROUP" '{arguments:{key:$key,value:$val,group:$grp}}')
get_payload=$(jq -nc --arg key "$MCP_KEY" --arg grp "$MCP_GROUP" '{arguments:{key:$key,group:$grp}}')

echo "INFO: PUT tool=$MCP_PUT_TOOL key=$MCP_KEY group=$MCP_GROUP value='$MCP_VALUE'"
put_response=$(call_tool "$MCP_PUT_TOOL" "$put_payload") || { echo "ERROR: PUT tool failed" >&2; exit 4; }
echo "INFO: PUT raw response: $put_response"

echo "INFO: GET tool=$MCP_GET_TOOL key=$MCP_KEY group=$MCP_GROUP"
get_response=$(call_tool "$MCP_GET_TOOL" "$get_payload") || { echo "ERROR: GET tool failed" >&2; exit 4; }
echo "INFO: GET raw response: $get_response"

# Response shapes handled: array of objects with .text containing JSON, object with content array, direct JSON object.
extract_value() {
  local raw=$1
  # 1. If raw parses directly and has .value
  if val=$(echo "$raw" | jq -er '.value' 2>/dev/null); then echo "$val"; return 0; fi
  # 2. If raw is array and first element.text is JSON containing value
  if val=$(echo "$raw" | jq -er '.[0].text' 2>/dev/null); then
    if inner=$(echo "$val" | jq -er '.value' 2>/dev/null); then echo "$inner"; return 0; fi
    if inner=$(echo "$val" 2>/dev/null | jq -er '.value' 2>/dev/null); then echo "$inner"; return 0; fi
    if inner=$(echo "$val" | jq -er 'try (fromjson | .value) // empty' 2>/dev/null); then echo "$inner"; return 0; fi
  fi
  # 3. If raw has content array with first text being embedded JSON
  if val=$(echo "$raw" | jq -er '.content[0].text' 2>/dev/null); then
    if inner=$(echo "$val" | jq -er '.value' 2>/dev/null); then echo "$inner"; return 0; fi
    if inner=$(echo "$val" | jq -er 'try (fromjson | .value) // empty' 2>/dev/null); then echo "$inner"; return 0; fi
  fi
  return 1
}

returned_value=$(extract_value "$get_response" || true)
if [[ -z "$returned_value" ]]; then
  echo "ERROR: Could not extract value from GET response" >&2
  exit 5
fi

if [[ "$returned_value" != "$MCP_VALUE" ]]; then
  echo "ERROR: Value mismatch. Sent '$MCP_VALUE' got '$returned_value'" >&2
  exit 5
fi

echo "SUCCESS: MCP round-trip verified value '$MCP_VALUE' (tool base: $MCP_CALL_BASE)"
exit 0
