#!/bin/bash

echo "=== MCP Server Diagnostics ==="

echo "1. Checking if python-mcp service is running..."
docker service ls | grep python-mcp

echo -e "\n2. Checking python-mcp service logs..."
docker service logs python-mcp --tail 20

echo -e "\n3. Checking if port 9123 is accessible from home-net..."
docker run --rm --network home-net alpine/curl:latest -v http://python-mcp:9123/mcp

echo -e "\n4. Testing basic connectivity to python-mcp service..."
docker run --rm --network home-net alpine ping -c 3 python-mcp

echo -e "\n=== End Diagnostics ==="