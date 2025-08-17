#!/usr/bin/env bash

# Require active conda/mamba env named 'openwebui'
expected_env="openwebui"
current_env="${CONDA_DEFAULT_ENV:-${MAMBA_DEFAULT_ENV:-}}"
if [[ "$current_env" != "$expected_env" ]]; then
    echo "Conda environment '$expected_env' not active." >&2
    echo "Activate with: conda activate $expected_env" >&2
    echo "Run the <prj-root>/build/create_openwebui_env.sh script to create the required conda environment."
    exit 1
fi

if [[ -z "${LITELLM_API_KEY:-}" ]]; then
    echo "Environment variable LITELLM_API_KEY is not set. Please export LITELLM_API_KEY before running this script." >&2
    echo "Create this key by logging into LiteLLM UI (http://localhost:4000/ui) as admin and creating a virtual key"
    echo "Team is mcp_tools with KeyType default"
    echo "The admin password is LITELLM_MASTER_KEY, which is set in the simple-oauth-dev-stack.yml file." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "The 'jq' utility is required but not installed." >&2
    echo "Install with: sudo apt-get update && sudo apt-get install -y jq" >&2
    exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "************* V E R I F Y  S W A R M ******************"
echo

if ! "${SCRIPT_DIR}/stack-verify.sh"; then
    echo "stack-verify.sh failed" >&2
    echo ">>> ERROR, Failed to verify SWARM"
    exit 1
fi

echo
echo "********** V E R I F Y  K E Y C L O A K  ***************"
echo

if ! "${SCRIPT_DIR}/key-cloak-verify.sh"; then
    echo "key-cloak-verify.sh failed" >&2
    echo ">>> ERROR, Failed to verify KeyCloak"
    exit 1
fi

echo
echo "********** V E R I F Y  M C P  S E R V E R *************"
echo

set +e
python3 "${SCRIPT_DIR}/../secure_mcp/test_mcp_client.py"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    echo "test_mcp_client.py exit code $rc (expected 0)" >&2
    echo ">>> ERROR, Failed to verify MCP Server"
    exit 1
fi

echo
echo "************ V E R I F Y  N G I N X  *******************"
echo

if ! "${SCRIPT_DIR}/nginx-verify.sh"; then
    echo "nginx-verify.sh failed" >&2
    echo ">>> ERROR, Failed to verify NGINX"
    exit 1
fi

echo
echo "********** V E R I F Y  L I T E L L M  ***************"
echo

if ! "${SCRIPT_DIR}/litellm-verify.sh"; then
    echo "litellm-verify.sh failed" >&2
    echo ">>> ERROR, Failed to verify LiteLLM"
    exit 1
fi

echo
echo "********* V E R I F Y  N G I N X  T O  M C P  **********"
echo

if ! "${SCRIPT_DIR}/nginx-verify.sh"; then
    echo "nginx-verify.sh failed" >&2
    echo ">>> ERROR, Failed to verify NGINX"
    exit 1
fi

echo
echo "********** V E R I F Y  V A U L T  ***************"
echo

if ! "${SCRIPT_DIR}/vault-verify.sh"; then
    echo "vault-verify.sh failed" >&2
    echo ">>> ERROR, Failed to verify Vault"
    exit 1
fi

echo
echo "******** C H E C K  V A U L T :  l i t e l l m _ a p i _ k e y ********"
echo

litellm_secret_name="litellm_api_key"
vault_token="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-root}}"
vault_path="${VAULT_LITELLM_PATH:-openwebui}"   # logical secret path
vault_mount="${VAULT_LITELLM_MOUNT:-secret}"   # kv mount

if [[ ! -f "${SCRIPT_DIR}/vault-lib.sh" ]]; then
    echo "vault-lib.sh missing; cannot check secret consistently." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/vault-lib.sh"

if ! declare -F vault_kv_get >/dev/null 2>&1; then
    echo "vault_kv_get not loaded from vault-lib.sh" >&2
    exit 1
fi

if vault_kv_get "$vault_token" "$vault_path" "$litellm_secret_name" "$vault_mount" >/dev/null 2>&1; then
    echo "Vault secret '${litellm_secret_name}' found at ${vault_mount}/${vault_path}."
else
    echo "Vault secret '${litellm_secret_name}' NOT found at ${vault_mount}/${vault_path}."
    echo
    echo "To create and store it:"  
    echo "1. Log in to LiteLLM UI:  http://localhost:4000/ui  (admin user)."  
    echo "2. Create a Virtual Key (Team: mcp_tools, KeyType: default). Copy the key."  
    echo "3. Export it:  export LITELLM_API_KEY=\"<copied-key>\""  
    echo "4. Store in Vault:  ${SCRIPT_DIR}/vault-set-litellm-key.sh --token $vault_token --value \"$LITELLM_API_KEY\""  
    echo "5. Re-run this script."  
fi