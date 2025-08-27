#!/bin/sh

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

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

# Clean up exited containers before build/deploy
echo "Cleaning up exited containers..."
if docker ps -aq -f status=exited | grep -q .; then
    docker rm $(docker ps -aq -f status=exited) >/dev/null 2>&1 || true
    echo "Removed exited containers."
else
    echo "No exited containers to remove."
fi

# Build image (Dockerfile lives alongside this script in main/; context is project root)
docker build -f "${SCRIPT_DIR}/Dockerfile" -t python-mcp "${ROOT_DIR}"

# Check if the python-mcp image was built successfully
echo "Checking if python-mcp image was built..."
while ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^python-mcp:latest$"; do
    echo "python-mcp image not found, waiting..."
    sleep 1
done
echo "python-mcp image build completed and verified."

# Deploy stack (compose file in swarm/ at project root)
docker stack deploy -c "${ROOT_DIR}/swarm/simple-oauth-dev-stack.yml" openwebui_stack