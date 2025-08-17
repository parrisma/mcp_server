#!/usr/bin/env bash
# openapi-compare.sh
# Compare a remote OpenAPI JSON served by nginx with the canonical local file.
# Default remote: http://localhost:9000/mcp/<MCP_SERVER_NAME>/openapi.json
# Default local : <repo-root>/mcp/<MCP_SERVER_NAME>/openapi.json
#
# Configuration (environment variables):
#   SCHEME           (default: http)
#   HOST             (default: localhost)
#   PORT             (default: 9000)
#   MCP_SERVER_NAME  (default: secure_datagroup)
#   REMOTE_PATH      (override full remote path; default uses MCP_SERVER_NAME: /mcp/${MCP_SERVER_NAME}/openapi.json)
#   LOCAL_FILE       (override full local file path; default: <repo-root>/mcp/${MCP_SERVER_NAME}/openapi.json)
#   MAX_RETRIES      (default: 10)
#   SLEEP_SECONDS    (default: 2)
#   EXPECT_STATUS    (default: 200)
#   IGNORE_PATHS     (space separated jq paths to delete before compare; optional)
#                     Example: IGNORE_PATHS='.servers[0].url .info.version'
#   CURL_EXTRA       (extra curl flags; optional)
#   QUIET            (set to 1 to reduce output)
#
# Exit Codes:
#   0 success (files equivalent after normalization / ignores)
#   1 missing dependency
#   2 local file missing
#   3 remote fetch failed / bad status
#   4 JSON parse error
#   5 mismatch
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

SCHEME=${SCHEME:-http}
HOST=${HOST:-localhost}
PORT=${PORT:-9000}
MCP_SERVER_NAME=${MCP_SERVER_NAME:-secure_datagroup}
REMOTE_PATH=${REMOTE_PATH:-/mcp/${MCP_SERVER_NAME}/openapi.json}
LOCAL_FILE=${LOCAL_FILE:-"${ROOT_DIR}/mcp/${MCP_SERVER_NAME}/openapi.json"}
MAX_RETRIES=${MAX_RETRIES:-10}
SLEEP_SECONDS=${SLEEP_SECONDS:-2}
EXPECT_STATUS=${EXPECT_STATUS:-200}
IGNORE_PATHS=${IGNORE_PATHS:-}
CURL_EXTRA=${CURL_EXTRA:-}
QUIET=${QUIET:-0}

log() { if [[ "$QUIET" != 1 ]]; then echo "$@"; fi }
err() { echo "$@" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || { err "ERROR: missing dependency: $1"; exit 1; }; }
need curl
need jq
need diff

if [[ ! -f "$LOCAL_FILE" ]]; then
  err "ERROR: Local OpenAPI file not found: $LOCAL_FILE"
  exit 2
fi

# Ensure REMOTE_PATH starts with /
if [[ "$REMOTE_PATH" != /* ]]; then
  REMOTE_PATH="/$REMOTE_PATH"
fi
REMOTE_URL="${SCHEME}://${HOST}:${PORT}${REMOTE_PATH}"

log "INFO: Local file : $LOCAL_FILE"
log "INFO: Remote URL : $REMOTE_URL"
log "INFO: Expect HTTP: $EXPECT_STATUS"

status=""
body_tmp="$(mktemp)" || { err "ERROR: mktemp failed"; exit 3; }
trap 'rm -f "$body_tmp" "$body_tmp.local" "$body_tmp.remote" "$body_tmp.local.norm" "$body_tmp.remote.norm"' EXIT

attempt=0
while (( attempt < MAX_RETRIES )); do
  attempt=$(( attempt + 1 ))
  # Use --fail-with-body so non-2xx still dumps body (curl 7.76+); fallback quietly if unsupported.
  if ! curl -sS -w '\n%{http_code}\n' $CURL_EXTRA -o "$body_tmp" "$REMOTE_URL" >"$body_tmp.status_raw" 2>/dev/null; then
    # fallback simpler status retrieval
    http_code=$(curl -s -o "$body_tmp" -w '%{http_code}' $CURL_EXTRA "$REMOTE_URL" || echo '000')
    echo "$http_code" > "$body_tmp.status_raw"
  fi
  http_code=$(tail -n1 "$body_tmp.status_raw" | tr -d '\r')
  if [[ "$http_code" == "$EXPECT_STATUS" ]]; then
    log "INFO: Got expected status $http_code on attempt $attempt"
    break
  fi
  log "WARN: Attempt $attempt/$MAX_RETRIES got status $http_code (want $EXPECT_STATUS); retrying in $SLEEP_SECONDS s"
  sleep "$SLEEP_SECONDS"
  http_code=""
done

if [[ "$http_code" != "$EXPECT_STATUS" ]]; then
  err "ERROR: Remote status did not become $EXPECT_STATUS (last: ${http_code:-none})"
  exit 3
fi

# Validate JSON parse for both local & remote
cp "$LOCAL_FILE" "$body_tmp.local"
cp "$body_tmp" "$body_tmp.remote"

if ! jq -S . "$body_tmp.local" > "$body_tmp.local.norm" 2>"$body_tmp.local.err"; then
  err "ERROR: Local file is not valid JSON: $LOCAL_FILE"
  sed 's/^/LOCAL JSON ERROR: /' "$body_tmp.local.err" >&2 || true
  exit 4
fi
if ! jq -S . "$body_tmp.remote" > "$body_tmp.remote.norm" 2>"$body_tmp.remote.err"; then
  err "ERROR: Remote response is not valid JSON: $REMOTE_URL"
  sed 's/^/REMOTE JSON ERROR: /' "$body_tmp.remote.err" >&2 || true
  exit 4
fi

apply_ignores() {
  local input_file=$1
  local output_file=$2
  if [[ -z "$IGNORE_PATHS" ]]; then
    cp "$input_file" "$output_file"
    return 0
  fi
  local jq_expr='.'
  for p in $IGNORE_PATHS; do
    jq_expr="del(${p}) | ${jq_expr}"
  done
  # Build a combined pipe; ensure deterministic sort again after deletions
  echo "$(jq -S "$jq_expr" "$input_file")" > "$output_file"
}

apply_ignores "$body_tmp.local.norm" "$body_tmp.local.norm.ignored"
apply_ignores "$body_tmp.remote.norm" "$body_tmp.remote.norm.ignored"

# Final diff
if diff -u "$body_tmp.local.norm.ignored" "$body_tmp.remote.norm.ignored" > "$body_tmp.diff"; then
  log "SUCCESS: Remote OpenAPI matches local canonical file."
  exit 0
else
  err "ERROR: OpenAPI documents differ. Showing unified diff:"
  sed 's/^/  /' "$body_tmp.diff" >&2
  err "Hint: use IGNORE_PATHS to ignore dynamic fields (e.g., IGNORE_PATHS='.servers[0].url .info.version')"
  exit 5
fi
