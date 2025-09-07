#!/usr/bin/env bash
# This script is a simple tester for secure_mcp/test_server.py.
# It sends a request with random bearer tokens and a payload to verify that
# test_server.py correctly logs/dumps incoming HTTP headers and JSON body.
# Not for production use—just a debugging aid.
set -euo pipefail

# Generate a 20-char random alphanumeric string
rand20() {
    # Guard against SIGPIPE with pipefail causing non-zero exit
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true
}

# Defaults
HOST="0.0.0.0"
PORT="9123"

usage() {
    echo "Usage: $0 [--host HOST] [--port PORT]"
    echo "Defaults: host=${HOST}, port=${PORT}"
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="${2:-}"
            shift 2
        ;;
        --port)
            PORT="${2:-}"
            shift 2
        ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
        ;;
    esac
done

BASE_URL="http://${HOST}:${PORT}"
echo "Using base URL: ${BASE_URL}" >&2

# Generate a random Bearer for x-mcp-securedata-auth
SECUREDATA_BEARER="sk-$(rand20)"
echo "Using x-mcp-securedata-auth Bearer: ${SECUREDATA_BEARER}" >&2
SECUREAUTH_BEARER="sk-$(rand20)"
echo "Using Authorization Bearer: ${SECUREAUTH_BEARER}" >&2
TESTKEY="key-$(rand20)"
echo "Using Test Key: ${TESTKEY}" >&2

# Build JSON payload with the TESTKEY value expanded
PAYLOAD=$(printf '{"arguments":{"key":"%s"}}' "${TESTKEY}")

# Run curl with trace to include request headers and body; capture all output
OUTPUT="$(curl -sS -L --trace-ascii - "${BASE_URL}/mcp/tools/call/test" \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${SECUREAUTH_BEARER}" \
    --header "x-mcp-securedata-auth: Bearer ${SECUREDATA_BEARER}" \
    --data "${PAYLOAD}" 2>&1 || true)"

echo "--- curl trace (first 80 lines) ---" >&2
printf '%s\n' "${OUTPUT}" | head -n 80 >&2
echo "-----------------------------------" >&2

# Verify tokens in the captured output
fail=0
if ! printf '%s' "${OUTPUT}" | grep -Fq "Authorization: Bearer ${SECUREAUTH_BEARER}"; then
    echo "ERROR: Authorization bearer not found in output" >&2
    fail=1
fi
if ! printf '%s' "${OUTPUT}" | grep -Fq "x-mcp-securedata-auth: Bearer ${SECUREDATA_BEARER}"; then
    echo "ERROR: x-mcp-securedata-auth bearer not found in output" >&2
    fail=1
fi
if ! printf '%s' "${OUTPUT}" | grep -Fq "${TESTKEY}"; then
    echo "ERROR: TESTKEY not found in output" >&2
    fail=1
fi

if [[ ${fail} -ne 0 ]]; then
    exit 1
fi

echo "All three random tokens were found in curl output." >&2