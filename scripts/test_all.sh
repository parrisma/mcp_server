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