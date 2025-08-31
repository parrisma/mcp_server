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

# Require exactly one argument: the stack name to remove
if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <stack_name>" >&2
    exit 1
fi

STACK="$1"
ensure_stack_removed "$STACK"