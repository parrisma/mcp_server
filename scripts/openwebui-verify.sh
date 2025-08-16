#!/bin/bash

# OpenWebUI verification script
# Checks that the OpenWebUI web interface is responding and (optionally) that login or API endpoints are available.

OWUI_HOST=${OWUI_HOST:-localhost}
OWUI_PORT=${OWUI_PORT:-8080}
OWUI_PROTOCOL=${OWUI_PROTOCOL:-http}
OWUI_PATH=${OWUI_PATH:-/}
OWUI_TIMEOUT=${OWUI_TIMEOUT:-5}
RETRIES=${RETRIES:-10}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-2}

BASE_URL="${OWUI_PROTOCOL}://${OWUI_HOST}:${OWUI_PORT}"
URL="${BASE_URL}${OWUI_PATH}"

echo "Checking OpenWebUI at ${URL} (retries=${RETRIES}, timeout=${OWUI_TIMEOUT}s)..."

ATTEMPT=1
while (( ATTEMPT <= RETRIES )); do
	HTTP_CODE=$(curl -k -s -o /tmp/openwebui_body.$$ -w '%{http_code}' \
		--max-time "$OWUI_TIMEOUT" \
		-H 'accept: text/html,application/json' \
		"$URL")

	if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
		echo "SUCCESS: OpenWebUI reachable (HTTP $HTTP_CODE)."
		TITLE=$(grep -i -m1 '<title>' /tmp/openwebui_body.$$ | sed -e 's/<[^>]*>//g' -e 's/^\s*//;s/\s*$//')
		[ -n "$TITLE" ] && echo "Page title: $TITLE"
		rm -f /tmp/openwebui_body.$$ 
		exit 0
	else
		echo "Attempt ${ATTEMPT}/${RETRIES}: HTTP ${HTTP_CODE}" >&2
		if (( ATTEMPT == RETRIES )); then
			echo "FAIL: OpenWebUI not reachable after ${RETRIES} attempts." >&2
			echo "Response snippet:" >&2
			head -c 500 /tmp/openwebui_body.$$ >&2
			rm -f /tmp/openwebui_body.$$ 
			exit 1
		fi
		sleep "$SLEEP_BETWEEN"
	fi
	((ATTEMPT++))
done

exit 1
