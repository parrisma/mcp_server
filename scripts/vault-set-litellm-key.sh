#!/usr/bin/env bash
# vault-set-litellm-key.sh
# Thin wrapper around vault-lib.sh to set & verify the LiteLLM API key using simple CLI args.
#
# Usage:
#   ./vault-set-litellm-key.sh --token <vault_token> --value sk-XXXX [--addr URL] [--mount secret] [--path openwebui] [--key litellm_api_key] [--debug]
#
# Short options:
#   -a, -t, -m, -p, -k, -v (value '-' reads from stdin). Use -h/--help for this text.
#
# Example use, with some defaults:
#    vault-set-litellm-key.sh --token root --key litellm_api_key --value <REDACTED>
#
# Behavior:
#   * Delegates to vault_kv_set in vault-lib.sh (handles KV v1/v2 + verification).
#
# Exit codes:
#   0 success
#   1 missing dependency
#   2 missing token
#   3 no value provided
#   4 mount lookup failed
#   5 write failed
#   6 verification mismatch

set -euo pipefail

err(){ echo "ERROR: $*" >&2; }
log(){ echo "INFO: $*" >&2; }
dbg(){ [[ ${DEBUG:-0} == 1 ]] && echo "DEBUG: $*" >&2 || true; }

need(){ command -v "$1" >/dev/null 2>&1 || { err "Missing dependency: $1"; exit 1; }; }
need curl; need jq
# shellcheck source=./vault-lib.sh
LIB_DIR="$(dirname "$0")"
if [[ -f "$LIB_DIR/vault-lib.sh" ]]; then
  # shellcheck disable=SC1091
  source "$LIB_DIR/vault-lib.sh"
else
  err "vault-lib.sh not found in $LIB_DIR"; exit 1
fi

usage(){ grep -E '^# ' "$0" | sed 's/^# //'; exit 0; }

VAULT_ADDR="http://localhost:8200"
VAULT_TOKEN=""
VAULT_KV_MOUNT="secret"
SECRET_BASE_PATH="openwebui"
SECRET_KEY_NAME="litellm_api_key"
SECRET_VALUE=""
DEBUG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--addr) VAULT_ADDR="$2"; shift 2;;
    -t|--token) VAULT_TOKEN="$2"; shift 2;;
    -m|--mount) VAULT_KV_MOUNT="$2"; shift 2;;
    -p|--path) SECRET_BASE_PATH="$2"; shift 2;;
    -k|--key) SECRET_KEY_NAME="$2"; shift 2;;
    -v|--value) SECRET_VALUE="$2"; shift 2;;
    --debug) DEBUG=1; shift;;
    -h|--help) usage;;
    --) shift; break;;
    *) err "Unknown arg: $1"; usage;;
  esac
done

if [[ "$SECRET_VALUE" == "-" ]]; then
  SECRET_VALUE=$(cat -)
fi

[[ -n "$VAULT_TOKEN" ]] || { err "No token provided (--token)"; exit 2; }
[[ -n "$SECRET_VALUE" ]] || { err "No secret value provided (--value or -)"; exit 3; }

VAULT_KV_MOUNT=${VAULT_KV_MOUNT%/}
log "Target: addr=$VAULT_ADDR mount=$VAULT_KV_MOUNT path=$SECRET_BASE_PATH key=$SECRET_KEY_NAME"

if vault_kv_set "$VAULT_TOKEN" "$SECRET_BASE_PATH" "$SECRET_KEY_NAME" "$SECRET_VALUE" "$VAULT_KV_MOUNT" "$VAULT_ADDR"; then
  log "Secret '$SECRET_KEY_NAME' set & verified."
  exit 0
else
  rc=$?
  err "Failed setting secret (rc=$rc)"
  exit "$rc"
fi
