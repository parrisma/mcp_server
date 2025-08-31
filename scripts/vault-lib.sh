#!/usr/bin/env bash
# vault-lib.sh
# Lightweight shared Vault helper functions for KV v1/v2 set/get.
# Defaults: addr=http://localhost:8200 mount=secret
# Requires: curl, jq
#
# Functions:
#   vault_kv_get <token> <path> <key> [mount] [addr]
#       Prints value to stdout. Exits 0 on success, 3 if not found, other >0 on error.
#   vault_kv_set <token> <path> <key> <value> [mount] [addr]
#       Writes value and verifies round-trip. Exits 0 on success.
#
# Notes:
#   <path> is the logical secret path under the mount (e.g. 'openwebui').
#   Detection of KV engine version is cached per mount+addr for the shell session.

set -euo pipefail

_vault_lib_need(){ command -v "$1" >/dev/null 2>&1 || { echo "vault-lib: missing dependency $1" >&2; exit 1; }; }
_vault_lib_need curl; _vault_lib_need jq

: "${VAULT_LIB_DEFAULT_ADDR:=http://localhost:8200}"
: "${VAULT_LIB_DEFAULT_MOUNT:=secret}"

# Cache associative array for versions
if declare -p _VAULT_KV_VERSION_CACHE >/dev/null 2>&1; then :; else declare -gA _VAULT_KV_VERSION_CACHE=(); fi

_vault_kv_detect_version(){
  local token="$1" mount="${2%/}" addr="${3:-$VAULT_LIB_DEFAULT_ADDR}" key="${addr}|${mount}"
  if [[ -n "${_VAULT_KV_VERSION_CACHE[$key]:-}" ]]; then
    echo "${_VAULT_KV_VERSION_CACHE[$key]}"; return 0
  fi
  local mounts resp version
  resp=$(curl -sS -H "X-Vault-Token: $token" "$addr/v1/sys/mounts" || true)
  if ! echo "$resp" | jq -e '.data' >/dev/null 2>&1; then
    echo "1"; return 0 # fallback
  fi
  version=$(echo "$resp" | jq -r ".data[\"${mount}/\"].options.version // \"1\"" 2>/dev/null || echo 1)
  case "$version" in 1|2) ;; *) version=1;; esac
  _VAULT_KV_VERSION_CACHE[$key]="$version"
  echo "$version"
}

vault_kv_get(){
  local token="$1" path="$2" key_name="$3" mount="${4:-$VAULT_LIB_DEFAULT_MOUNT}" addr="${5:-$VAULT_LIB_DEFAULT_ADDR}" version read_url jq_filter resp value
  version=$(_vault_kv_detect_version "$token" "$mount" "$addr")
  if [[ "$version" == 2 ]]; then
    read_url="$addr/v1/${mount}/data/${path}"
    jq_filter=".data.data[\"$key_name\"] // empty"
  else
    read_url="$addr/v1/${mount}/${path}"
    jq_filter=".data[\"$key_name\"] // empty"
  fi
  resp=$(curl -sS -H "X-Vault-Token: $token" "$read_url" || true)
  value=$(echo "$resp" | jq -r "$jq_filter")
  if [[ -z "$value" || "$value" == "null" ]]; then
    return 3
  fi
  printf '%s' "$value"
  return 0
}

vault_kv_set(){
  local token="$1" path="$2" key_name="$3" value="$4" mount="${5:-$VAULT_LIB_DEFAULT_MOUNT}" addr="${6:-$VAULT_LIB_DEFAULT_ADDR}" version write_url read_url payload rc read_back
  version=$(_vault_kv_detect_version "$token" "$mount" "$addr")
  if [[ "$version" == 2 ]]; then
    write_url="$addr/v1/${mount}/data/${path}"
    read_url="$write_url"
    payload=$(jq -n --arg k "$key_name" --arg v "$value" '{data:{($k):$v}}')
  else
    write_url="$addr/v1/${mount}/${path}"
    read_url="$write_url"
    payload=$(jq -n --arg k "$key_name" --arg v "$value" '{($k):$v}')
  fi
  local status
  #echo "+ curl -sS -o /dev/null -w '%{http_code}' -H 'X-Vault-Token: $token' -H 'Content-Type: application/json' -X POST \"$write_url\" -d '***REDACTED***'" >&2
  status=$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Vault-Token: $token" -H 'Content-Type: application/json' -X POST "$write_url" -d "$payload" || echo 000)
  if [[ "$status" != 200 && "$status" != 204 ]]; then
    echo "vault-lib: write failed HTTP $status" >&2
    return 5
  fi
  read_back=$(vault_kv_get "$token" "$path" "$key_name" "$mount" "$addr" || rc=$?) || rc=$?
  if [[ ${rc:-0} -ne 0 ]]; then
    echo "vault-lib: verification read failed (rc=${rc:-?})" >&2
    return 6
  fi
  if [[ "$read_back" != "$value" ]]; then
    echo "vault-lib: verification mismatch" >&2
    return 6
  fi
  return 0
}

# End of vault-lib.sh
