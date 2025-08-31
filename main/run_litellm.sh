#!/bin/sh

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# Source util.sh (try script dir, then project root)
if [ -f "${SCRIPT_DIR}/utils.sh" ]; then
    . "${SCRIPT_DIR}/utils.sh"
    elif [ -f "${ROOT_DIR}/utils.sh" ]; then
    . "${ROOT_DIR}/utils.sh"
else
    echo "Error: utils.sh not found in ${SCRIPT_DIR} or ${ROOT_DIR}" >&2
    exit 1
fi

ensure_stack_removed "litellm"

# Wait a bit more for network cleanup
sleep 3

create_and_verify_network home-net 300 overlay true
create_and_verify_network proxy 300 overlay true

cleanup_exited_containers

deploy_and_verify_stack litellm "$ROOT_DIR/swarm/litellm.yml" 300