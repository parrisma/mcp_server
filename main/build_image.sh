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

cleanup_exited_containers

build_and_verify_image "${SCRIPT_DIR}/Dockerfile" "python-mcp" "latest" "${ROOT_DIR}"
