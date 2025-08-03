#!/bin/bash

# Ensure Python output is not buffered (for immediate log visibility)
export PYTHONUNBUFFERED=1

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Container starting up..."
log "Environment variables:"
log "  MCP_SERVER=${MCP_SERVER:-not set}"
log "  MCP_TEST=${MCP_TEST:-not set}"
log "  MCPO_PROXY=${MCPO_PROXY:-not set}"
log "  MCPO_HOST=${MCPO_HOST:-0.0.0.0}"
log "  MCPO_PORT=${MCPO_PORT:-8123}"
log "  MCPO_SERVER_TYPE=${MCPO_SERVER_TYPE:-streamable-http}"
log "  MCPO_TARGET_URL=${MCPO_TARGET_URL:-not set}"
log "  LITELLM_PROXY=${LITELLM_PROXY:-not set}"
log "  LITELLM_HOST=${LITELLM_HOST:-0.0.0.0}"
log "  LITELLM_PORT=${LITELLM_PORT:-4000}"
log "  LITELLM_CONFIG=${LITELLM_CONFIG:-/app/litellm-config.yaml}"

if [ "$MCP_SERVER" = "1" ] || [ "$MCP_SERVER" = "true" ]; then
    log "Starting MCP Server..."
    log "Executing: python -u ./mcp_server/server.py"
    exec python -u ./mcp_server/server.py
elif [ "$MCP_TEST" = "1" ] || [ "$MCP_TEST" = "true" ]; then
    log "Running MCP Test Client..."
    log "Executing: python -u ./mcp_server/mcp_test_client.py"
    exec python -u ./mcp_server/mcp_test_client.py
elif [ "$MCPO_PROXY" = "1" ] || [ "$MCPO_PROXY" = "true" ]; then
    log "Starting MCPO Proxy Server..."
    
    # Set default values if not provided
    MCPO_HOST=${MCPO_HOST:-0.0.0.0}
    MCPO_PORT=${MCPO_PORT:-9123}
    MCPO_SERVER_TYPE=${MCPO_SERVER_TYPE:-streamable_http}
    
    # Check if target URL is provided
    if [ -z "$MCPO_TARGET_URL" ]; then
        log "ERROR: MCPO_TARGET_URL environment variable is required when MCPO_PROXY=true"
        log "Example: MCPO_TARGET_URL=http://localhost:8123/mcp"
        exit 1
    fi
    
    # Check if mcpo command is available
    if ! command -v mcpo &> /dev/null; then
        log "ERROR: mcpo command not found. Please ensure it's installed and in PATH."
        log "You may need to install it or adjust the PATH to include the conda environment."
        exit 1
    fi
    
    # Build the mcpo command
    MCPO_CMD="mcpo --host ${MCPO_HOST} --port ${MCPO_PORT} --server-type ${MCPO_SERVER_TYPE} -- ${MCPO_TARGET_URL}"
    
    log "MCPO Configuration:"
    log "  Host: ${MCPO_HOST}"
    log "  Port: ${MCPO_PORT}"
    log "  Server Type: ${MCPO_SERVER_TYPE}"
    log "  Target URL: ${MCPO_TARGET_URL}"
    log "Executing: ${MCPO_CMD}"
    
    exec mcpo --host "${MCPO_HOST}" --port "${MCPO_PORT}" --server-type "${MCPO_SERVER_TYPE}" -- "${MCPO_TARGET_URL}"
elif [ "$LITELLM_PROXY" = "1" ] || [ "$LITELLM_PROXY" = "true" ]; then
    log "Starting LiteLLM Proxy Server with MCP Support..."
    
    # Set default values if not provided
    LITELLM_HOST=${LITELLM_HOST:-0.0.0.0}
    LITELLM_PORT=${LITELLM_PORT:-4000}
    LITELLM_CONFIG=${LITELLM_CONFIG:-/app/litellm-config.yaml}
    
    # Check if config file exists
    if [ ! -f "$LITELLM_CONFIG" ]; then
        log "ERROR: LiteLLM config file not found at ${LITELLM_CONFIG}"
        log "Please ensure the config file exists or set LITELLM_CONFIG environment variable"
        exit 1
    fi
    
    # Check if litellm command is available
    if ! command -v litellm &> /dev/null; then
        log "ERROR: litellm command not found. Please ensure it's installed and in PATH."
        exit 1
    fi
    
    log "LiteLLM Configuration:"
    log "  Host: ${LITELLM_HOST}"
    log "  Port: ${LITELLM_PORT}"
    log "  Config File: ${LITELLM_CONFIG}"
    log "  OAuth Header Forwarding: Enabled"
    log "Executing: litellm --config ${LITELLM_CONFIG} --host ${LITELLM_HOST} --port ${LITELLM_PORT}"
    
    exec litellm --config "${LITELLM_CONFIG}" --host "${LITELLM_HOST}" --port "${LITELLM_PORT}"
else
    log "No environment variable set. Running infinite loop..."
    log "Container will sleep for 60 seconds between log messages"
    counter=1
    while true; do
        log "Heartbeat #${counter} - Container is alive"
        sleep 60
        counter=$((counter + 1))
    done
fi