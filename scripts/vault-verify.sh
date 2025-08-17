#!/usr/bin/env bash
# vault-verify.sh
# Verify that a HashiCorp Vault instance is reachable, initialized, unsealed, and
# that a provided root (or other) token has sufficient privileges (list mounts,
# optionally write/read a test secret).
#
# Environment variables:
#   VAULT_ADDR          (default: http://localhost:8200)
#   VAULT_TOKEN         (preferred token variable)
#   VAULT_ROOT_TOKEN    (fallback token variable if VAULT_TOKEN unset)
#   VAULT_MAX_RETRIES   (default: 20) attempts to poll health
#   VAULT_SLEEP_SECONDS (default: 2)  delay between retries
#   VAULT_EXPECT_INIT   (default: true) require initialized=true
#   VAULT_EXPECT_UNSEALED (default: true) require sealed=false
#   VAULT_TEST_SECRET   (default: 1) set to 0 to skip write/read round-trip
#   VAULT_KV_PATH       (default: secret) base mount for kv engine
#   VAULT_DEBUG         (default: 0) set 1 for verbose debug output
#
# Exit codes:
#   0 success
#   1 missing dependency
#   2 cannot reach health endpoint
#   3 health state invalid (not initialized / sealed) per expectations
#   4 token not provided
#   5 token invalid (cannot list mounts)
#   6 write/read secret mismatch
#   7 unexpected error (parse etc.)

set -euo pipefail

VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200}
VAULT_MAX_RETRIES=${VAULT_MAX_RETRIES:-20}
VAULT_SLEEP_SECONDS=${VAULT_SLEEP_SECONDS:-2}
VAULT_EXPECT_INIT=${VAULT_EXPECT_INIT:-true}
VAULT_EXPECT_UNSEALED=${VAULT_EXPECT_UNSEALED:-true}
VAULT_TEST_SECRET=${VAULT_TEST_SECRET:-1}
VAULT_KV_PATH=${VAULT_KV_PATH:-secret}
VAULT_DEBUG=${VAULT_DEBUG:-0}

err(){ echo "ERROR: $*" >&2; }
log(){ echo "INFO: $*" >&2; }
dbg(){ (( VAULT_DEBUG )) && echo "DEBUG: $*" >&2 || true; }

need(){ command -v "$1" >/dev/null 2>&1 || { err "Missing dependency: $1"; exit 1; }; }
need curl
need jq

# shellcheck source=./vault-lib.sh
LIB_DIR="$(dirname "$0")"
if [[ -f "$LIB_DIR/vault-lib.sh" ]]; then
  # shellcheck disable=SC1091
  source "$LIB_DIR/vault-lib.sh"
else
  dbg "vault-lib.sh not found alongside script; proceeding without KV helper (secret test may fail)"
fi

# token resolution
if [[ -z "${VAULT_TOKEN:-}" && -n "${VAULT_ROOT_TOKEN:-}" ]]; then
  VAULT_TOKEN=$VAULT_ROOT_TOKEN
fi
if [[ -z "${VAULT_TOKEN:-}" ]]; then
  err "No VAULT_TOKEN or VAULT_ROOT_TOKEN provided, check the swarm script where this token is set"; exit 4
fi

log "Checking Vault health at $VAULT_ADDR"

attempt=0
health_json=""
http_code=""
while (( attempt < VAULT_MAX_RETRIES )); do
  attempt=$((attempt+1))
  response=$(curl -sS -w '\n%{http_code}' "$VAULT_ADDR/v1/sys/health" || true)
  # Last line is status code
  http_code=$(echo "$response" | tail -n1 | tr -d '\r')
  # All previous lines comprise JSON (can be multi-line on errors)
  health_json=$(echo "$response" | sed '$d')
  if [[ -n "$health_json" ]]; then
    init=$(echo "$health_json" | jq -r 'try .initialized // empty' 2>/dev/null || true)
    sealed=$(echo "$health_json" | jq -r 'try .sealed // empty' 2>/dev/null || true)
    if [[ -n "$init" && -n "$sealed" ]]; then
      dbg "Health attempt $attempt code=$http_code init=$init sealed=$sealed"
      break
    fi
  fi
  dbg "Health attempt $attempt incomplete (code=$http_code); retrying in $VAULT_SLEEP_SECONDS s"
  sleep "$VAULT_SLEEP_SECONDS"
done

if [[ -z "$health_json" ]]; then
  err "Unable to retrieve health after $VAULT_MAX_RETRIES attempts"; exit 2
fi

init=$(echo "$health_json" | jq -r 'try .initialized // ""')
sealed=$(echo "$health_json" | jq -r 'try .sealed // ""')

log "Health: initialized=$init sealed=$sealed http_code=$http_code"

# Some dev / certain builds may omit 'sealed' in /sys/health when 200; infer via seal-status or http_code
if [[ -z "$sealed" ]]; then
  seal_status=$(curl -sS "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null || true)
  inferred=$(echo "$seal_status" | jq -r 'try .sealed // ""' 2>/dev/null || true)
  if [[ -n "$inferred" ]]; then
    sealed="$inferred"
    dbg "Inferred sealed=$sealed from seal-status"
  elif [[ "$http_code" == 200 && "$init" == true ]]; then
    # Health 200 + initialized true implies unsealed
    sealed=false
    dbg "Assuming sealed=false based on health code 200 & initialized=true"
  fi
  log "Adjusted sealed state: $sealed" 
fi

if [[ "$VAULT_EXPECT_INIT" == true && "$init" != true ]]; then
  err "Vault not initialized (initialized=$init)"; exit 3
fi
if [[ "$VAULT_EXPECT_UNSEALED" == true && "$sealed" != false ]]; then
  err "Vault is sealed (sealed=$sealed)"; exit 3
fi

# Validate token by listing mounts
dbg "Validating token via /v1/sys/mounts"
mounts_resp=$(curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/mounts" || true)
if ! echo "$mounts_resp" | jq -e '.data' >/dev/null 2>&1; then
  err "Token invalid or insufficient privileges (cannot list mounts)."; exit 5
fi
log "Token access confirmed (mounts listed)."

if [[ "$VAULT_TEST_SECRET" != 1 ]]; then
  log "Skipping secret write/read test (VAULT_TEST_SECRET != 1)."
  echo "SUCCESS: Vault verification passed (no secret test)."
  exit 0
fi

if ! declare -F vault_kv_set >/dev/null 2>&1; then
  err "vault-lib functions unavailable; cannot perform secret round-trip"; exit 7
fi

test_name="vault_verify_$(date +%s)_$RANDOM"
test_value="pong-${RANDOM}"
dbg "Performing KV round-trip via vault-lib: mount=$VAULT_KV_PATH path=$test_name key=ping value=$test_value"

if vault_kv_set "$VAULT_TOKEN" "$test_name" "ping" "$test_value" "$VAULT_KV_PATH" "$VAULT_ADDR"; then
  # Optional second read using vault_kv_get (vault_kv_set already verifies)
  if retrieved=$(vault_kv_get "$VAULT_TOKEN" "$test_name" "ping" "$VAULT_KV_PATH" "$VAULT_ADDR" 2>/dev/null); then
    log "Secret round-trip succeeded (value=$retrieved)."
    echo "SUCCESS: Vault verification passed."
    exit 0
  else
    err "Post-verification read failed"; exit 6
  fi
else
  rc=$?
  err "KV round-trip failed (rc=$rc)"; exit 6
fi
