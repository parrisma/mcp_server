#!/usr/bin/env bash
set -euo pipefail

# If not exactly two arguments are provided, explain what is expected (do not exit).
if [[ $# -ne 2 ]]; then
    echo "Expected exactly 2 arguments:"
    echo "  1) base_url - LiteLLM-to-OpenWebUI base URL (e.g., http://localhost:8087)"
    echo "  2) openwebui_oauth_key - OAuth bearer token for OpenWebUI (used for Authorization header)"
    echo "Note: base_url defaults to http://localhost:8087 if omitted, and the OAuth key can be read from OPENWEBUI_OAUTH_KEY."
    echo "Details:"
    echo "  - The openwebui_oauth_key you pass as the Authorization: Bearer token is used as the 'key' name to look up the corresponding LiteLLM virtual key for the LiteLLM call."
    echo "  - The same OAuth key is also provided to the MCP server in the JSON payload (-d '{...}') as the 'key' value when required by the tool."
fi

LITELLM_TO_OPENWEB_URL="${1:-http://localhost:8087}"
# If no scheme provided, assume http
if [[ "$LITELLM_TO_OPENWEB_URL" != *"://"* ]]; then
    LITELLM_TO_OPENWEB_URL="http://${LITELLM_TO_OPENWEB_URL}"
fi
# Strip trailing slash
LITELLM_TO_OPENWEB_URL="${LITELLM_TO_OPENWEB_URL%/}"

# Second arg: OpenWebUI OAuth key (or use OPENWEBUI_OAUTH_KEY env var)
OPENWEBUI_OAUTH_KEY="${2:-${OPENWEBUI_OAUTH_KEY:-}}"
if [[ -z "${OPENWEBUI_OAUTH_KEY}" ]]; then
    echo "Usage: $(basename "$0") [base_url] <openwebui_oauth_key>" >&2
    exit 1
fi

# Generate a random 32-hex-character value and print it
if command -v openssl >/dev/null 2>&1; then
    RANDOM_VALUE="$(openssl rand -hex 16)"
    elif command -v hexdump >/dev/null 2>&1; then
    RANDOM_VALUE="$(hexdump -v -n 16 -e '/1 "%02x"' /dev/urandom)"
else
    RANDOM_VALUE="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi

KEY="test_key"
GROUP="test_group"

echo "LiteLLM to OpenWebUI URL: ${LITELLM_TO_OPENWEB_URL}"
echo "OpenWebUI OAuth key: ${OPENWEBUI_OAUTH_KEY}"
echo "Random value: ${RANDOM_VALUE}"

curl -fS -X POST "${LITELLM_TO_OPENWEB_URL}/mcp-rest/tools/call/secure_datagroup-put_key_value" \
-H "Authorization: Bearer ${OPENWEBUI_OAUTH_KEY}" \
-H "Content-Type: application/json" \
-d "$(jq -n --arg k "$KEY" --arg v "$RANDOM_VALUE" --arg g "$GROUP" '{arguments:{key:$k, value:$v, group:$g}}')" \
|| { echo "Error: secure_datagroup-put_key_value request failed" >&2; exit 1; }

GET_RESP=$(curl -fsS -X POST "${LITELLM_TO_OPENWEB_URL}/mcp-rest/tools/call/secure_datagroup-get_value_by_key" \
    -H "Authorization: Bearer ${OPENWEBUI_OAUTH_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg k "$KEY" --arg g "$GROUP" '{arguments:{key:$k, group:$g}}')"
) || { echo "Error: secure_datagroup-get_value_by_key request failed" >&2; exit 1; }

echo "Raw get_value_by_key response: ${GET_RESP}"

# The tool response is an array; find the first text item. Keep it as a JSON string (no -r),
# so that fromjson can parse it in the next step.
if ! NESTED_JSON=$(printf '%s' "$GET_RESP" | jq -e '[.[] | select(.type=="text")][0].text'); then
    echo "Error: Unable to extract .text from tool response." >&2
    echo "$GET_RESP" >&2
    exit 1
fi

if ! RETURNED_VALUE=$(printf '%s' "$NESTED_JSON" | jq -er 'fromjson | .value'); then
    echo "Error: Unable to parse .value from nested JSON text." >&2
    echo "$NESTED_JSON" >&2
    exit 1
fi

if [[ "$RETURNED_VALUE" == "$RANDOM_VALUE" ]]; then
    echo "SUCCESS: Returned value matches the random value passed."
    exit 0
else
    echo "MISMATCH: Returned value does not match. Expected=${RANDOM_VALUE} Got=${RETURNED_VALUE}" >&2
    exit 2
fi

