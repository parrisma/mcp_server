#!/bin/sh

# Remove the stack and wait for it to complete
docker stack rm openwebui_stack

# Wait for stack removal to complete by checking if services still exist
echo "Waiting for stack removal to complete..."
while docker service ls --filter label=com.docker.stack.namespace=openwebui_stack --quiet | grep -q .; do
    echo "Stack still removing, waiting..."
    sleep 2
done
echo "Stack removal completed."

# Wait a bit more for network cleanup
sleep 3

# Remove networks (ignore errors if they don't exist)
docker network rm home-net 2>/dev/null || true
docker network rm proxy 2>/dev/null || true

# Wait for networks to be completely removed
echo "Waiting for networks to be removed..."
while docker network ls --format "{{.Name}}" | grep -E "^(home-net|proxy)$" > /dev/null; do
    echo "Networks still exist, waiting..."
    sleep 1
done
echo "Networks removal completed."

# Create networks
docker network create --driver overlay --attachable home-net
docker network create --driver overlay --attachable proxy

# Wait for networks to be created
echo "Waiting for networks to be created..."
while ! docker network ls --format "{{.Name}}" | grep -E "^(home-net|proxy)$" | wc -l | grep -q "2"; do
    echo "Networks still creating, waiting..."
    sleep 1
done
echo "Networks creation completed."

# Build image
docker build -t python-mcp .

# Check if the python-mcp image was built successfully
echo "Checking if python-mcp image was built..."
while ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^python-mcp:latest$"; do
    echo "python-mcp image not found, waiting..."
    sleep 1
done
echo "python-mcp image build completed and verified."

# Deploy stack
docker stack deploy -c simple-oauth-dev-stack.yml openwebui_stack