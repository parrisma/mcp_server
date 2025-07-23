#!/bin/bash

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Container starting up..."
log "Environment variables:"
log "  MCP_SERVER=${MCP_SERVER:-not set}"
log "  MCP_TEST=${MCP_TEST:-not set}"

if [ "$MCP_SERVER" = "1" ] || [ "$MCP_SERVER" = "true" ]; then
    log "Starting MCP Server..."
    log "Executing: python ./mcp_server/server.py"
    exec python ./mcp_server/server.py
elif [ "$MCP_TEST" = "1" ] || [ "$MCP_TEST" = "true" ]; then
    log "Running MCP Test Client..."
    log "Executing: python ./mcp_server/mcp_test_client.py"
    exec python ./mcp_server/mcp_test_client.py
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