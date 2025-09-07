#!/bin/sh

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# Source util.sh (try script dir, then project root)
if [ -f "${SCRIPT_DIR}/util.sh" ]; then
    . "${SCRIPT_DIR}/util.sh"
    elif [ -f "${ROOT_DIR}/util.sh" ]; then
    . "${ROOT_DIR}/util.sh"
else
    echo "Error: util.sh not found in ${SCRIPT_DIR} or ${ROOT_DIR}" >&2
    exit 1
fi

ensure_stack_removed "openwebui"
ensure_stack_removed "litellm"
ensure_stack_removed "mcp"
ensure_stack_removed "keycloak"
ensure_stack_removed "vault"

ensure_network_removed "home-net"
ensure_network_removed "proxy"

create_and_verify_network home-net 300 overlay true
create_and_verify_network proxy 300 overlay true

cleanup_exited_containers

build_and_verify_image "${SCRIPT_DIR}/Dockerfile" "python-mcp" "latest" "${ROOT_DIR}"

deploy_and_verify_stack vault "$ROOT_DIR/swarm/vault.yml" 300
deploy_and_verify_stack keycloak "$ROOT_DIR/swarm/keycloak.yml" 300
deploy_and_verify_stack keycloak "$ROOT_DIR/swarm/mcp_server.yml" 300
deploy_and_verify_stack keycloak "$ROOT_DIR/swarm/litellm.yml" 300
deploy_and_verify_stack keycloak "$ROOT_DIR/swarm/openwebui.yml" 300

