#!/bin/bash

echo "Testing MCP client connection to server in Docker stack..."

# Test with the correct server URL for Docker network
docker run -it --rm --network home-net \
  -e MCP_TEST=1 \
  -e MCP_SERVER_URL=http://python-mcp:9123/mcp \
  python-mcp:latest