#!/bin/bash

# LiteLLM verification script
# Checks health endpoint and exits non-zero on failure.

LITELLM_HOST=${LITELLM_HOST:-localhost}
LITELLM_PORT=${LITELLM_PORT:-4000}
LITELLM_HEALTH_PATH=${LITELLM_HEALTH_PATH:-/v1/mcp/server/health}
LITELLM_TOOLS_PATH=${LITELLM_TOOLS_PATH:-/mcp-rest/tools/list}
LITELLM_PROTOCOL=${LITELLM_PROTOCOL:-http}
LITELLM_TIMEOUT=${LITELLM_TIMEOUT:-5}
RETRIES=${RETRIES:-5}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-2}

# API key precedence: first non-empty among
# 1) CLI arg --api-key=VALUE or -k VALUE
# 2) Environment variable LITELLM_API_KEY (not overridden here)
# 3) Environment variable OPENAI_API_KEY (fallback)

API_KEY=""
for ARG in "$@"; do
	case $ARG in
		--api-key=*) API_KEY="${ARG#*=}" ; shift ;;
	esac
done

# Support -k VALUE form
while getopts ":k:" opt; do
	case $opt in
		k) API_KEY="$OPTARG" ;;
	esac
done

if [ -z "$API_KEY" ]; then
	if [ -n "$LITELLM_API_KEY" ]; then
		API_KEY="$LITELLM_API_KEY"
	elif [ -n "$OPENAI_API_KEY" ]; then
		API_KEY="$OPENAI_API_KEY"
	fi
fi

if [ -z "$API_KEY" ]; then
	echo "ERROR: No API key provided. Use --api-key=, -k, or set LITELLM_API_KEY (or OPENAI_API_KEY)." >&2
	exit 2
fi

BASE_URL="${LITELLM_PROTOCOL}://${LITELLM_HOST}:${LITELLM_PORT}"
URL="${BASE_URL}${LITELLM_HEALTH_PATH}"

echo "Checking LiteLLM health at ${URL} (retries=${RETRIES}, timeout=${LITELLM_TIMEOUT}s)..."

ATTEMPT=1
while (( ATTEMPT <= RETRIES )); do
	HTTP_CODE=$(curl -s -o /tmp/litellm_health_body.$$ -w '%{http_code}' \
		-H 'accept: application/json' \
		-H "Authorization: Bearer ${API_KEY}" \
		--max-time "$LITELLM_TIMEOUT" \
		"$URL")

	if [ "$HTTP_CODE" = "200" ]; then
		echo "SUCCESS: LiteLLM healthy (HTTP 200)."
		cat /tmp/litellm_health_body.$$ | jq '.  // {}' 2>/dev/null || cat /tmp/litellm_health_body.$$
		rm -f /tmp/litellm_health_body.$$
		HEALTH_OK=1
		break
	else
		echo "Attempt ${ATTEMPT}/${RETRIES}: HTTP ${HTTP_CODE}" >&2
		if (( ATTEMPT == RETRIES )); then
			echo "FAIL: LiteLLM health check failed after ${RETRIES} attempts." >&2
			echo "Response body:" >&2
			cat /tmp/litellm_health_body.$$ >&2
			rm -f /tmp/litellm_health_body.$$
			exit 1
		fi
		sleep "$SLEEP_BETWEEN"
	fi
	((ATTEMPT++))
done

if [ "${HEALTH_OK:-0}" != "1" ]; then
	exit 1
fi

# ---- Tools verification ----
EXPECTED_TOOLS_DEFAULT="secure_datagroup-put_key_value secure_datagroup-get_value_by_key secure_datagroup-test"
# Allow override via EXPECTED_TOOLS env var
EXPECTED_TOOLS=${EXPECTED_TOOLS:-$EXPECTED_TOOLS_DEFAULT}

TOOLS_URL="${BASE_URL}${LITELLM_TOOLS_PATH}"
echo "Checking LiteLLM tools at ${TOOLS_URL} ..."

TOOLS_RESPONSE=$(curl -s -w '\n%{http_code}' -H 'accept: application/json' -H "Authorization: Bearer ${API_KEY}" --max-time "$LITELLM_TIMEOUT" "$TOOLS_URL") || {
	echo "ERROR: Failed to call tools endpoint" >&2; exit 3; }

TOOLS_HTTP_CODE=$(echo "$TOOLS_RESPONSE" | tail -n1)
TOOLS_BODY=$(echo "$TOOLS_RESPONSE" | sed '$d')

if [ "$TOOLS_HTTP_CODE" != "200" ]; then
	echo "ERROR: Tools endpoint returned HTTP $TOOLS_HTTP_CODE" >&2
	echo "Body:" >&2
	echo "$TOOLS_BODY" >&2
	exit 4
fi

TOOL_NAMES=$(echo "$TOOLS_BODY" | jq -r '.tools[].name' 2>/dev/null)
if [ -z "$TOOL_NAMES" ]; then
	echo "ERROR: Could not parse tool names from response (jq empty). Raw body:" >&2
	echo "$TOOLS_BODY" >&2
	exit 5
fi

echo "Discovered tools:" 
echo "$TOOL_NAMES" | sed 's/^/  - /'

MISSING=()
for NEED in $EXPECTED_TOOLS; do
	echo "$TOOL_NAMES" | grep -qx "$NEED" || MISSING+=("$NEED")
done

if [ ${#MISSING[@]} -gt 0 ]; then
	echo "FAIL: Missing expected tools: ${MISSING[*]}" >&2
	exit 6
fi

echo "SUCCESS: All expected tools present." 
exit 0
