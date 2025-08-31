#!/bin/sh

ensure_stack_removed() {
    stack_name="$1"
    # Optional timeout (seconds), defaults to 300
    timeout="${2:-300}"
    interval=2
    attempts=$(( (timeout + interval - 1) / interval ))
    
    if [ -z "$stack_name" ]; then
        echo "Error: function utils.sh:ensure_stack_removed requires a stack name." >&2
        return 1
    fi
    
    # Remove the stack only if it exists
    if docker stack ls --format '{{.Name}}' 2>/dev/null | grep -Fxq "$stack_name"; then
        echo "Removing existing stack '$stack_name'..."
        if ! docker stack rm "$stack_name"; then
            echo "Error: failed to initiate removal of stack '$stack_name'." >&2
            return 1
        fi
        
        echo "Waiting for stack '$stack_name' to be fully removed (timeout: ${timeout}s)..."
        i=0
        while [ "$i" -lt "$attempts" ]; do
            # Stack no longer listed?
            if ! docker stack ls --format '{{.Name}}' 2>/dev/null | grep -Fxq "$stack_name"; then
                # No services left for this stack?
                if ! docker service ls --format '{{.Name}}' --filter "label=com.docker.stack.namespace=$stack_name" 2>/dev/null | grep -q .; then
                    echo "Stack '$stack_name' removed."
                    return 0
                fi
            fi
            sleep "$interval"
            i=$((i + 1))
        done
        
        echo "Warning: timed out waiting for stack '$stack_name' to be removed after ${timeout}s." >&2
        return 2
    else
        echo "Stack '$stack_name' not found; skipping removal."
        return 0
    fi
}

ensure_network_removed() {
    net_name="$1"
    timeout="${2:-300}"
    interval=2
    attempts=$(( (timeout + interval - 1) / interval ))
    
    if [ -z "$net_name" ]; then
        echo "Error: function utils.sh:ensure_network_removed requires a network name." >&2
        return 1
    fi
    
    if docker network inspect "$net_name" >/dev/null 2>&1; then
        echo "Removing network '$net_name'..."
        if ! docker network rm "$net_name" >/dev/null 2>&1; then
            echo "Error: failed to remove network '$net_name'." >&2
            return 1
        fi
        
        echo "Waiting for network '$net_name' to disappear (timeout: ${timeout}s)..."
        i=0
        while [ "$i" -lt "$attempts" ]; do
            if ! docker network inspect "$net_name" >/dev/null 2>&1; then
                echo "Network '$net_name' removed."
                return 0
            fi
            sleep "$interval"
            i=$((i + 1))
        done
        
        echo "Warning: timed out waiting for network '$net_name' to be removed after ${timeout}s." >&2
        return 2
    else
        echo "Network '$net_name' not found; skipping removal."
        return 0
    fi
}

create_and_verify_network() {
    net_name="$1"
    timeout="${2:-300}"
    driver="${3:-overlay}"
    attachable="${4:-true}"
    
    if [ -z "$net_name" ]; then
        echo "Error: function utils.sh:ensure_network_present requires a network name." >&2
        return 1
    fi
    
    interval=2
    attempts=$(( (timeout + interval - 1) / interval ))
    
    if docker network inspect "$net_name" >/dev/null 2>&1; then
        echo "Network '$net_name' already exists."
        drv=$(docker network inspect -f '{{.Driver}}' "$net_name" 2>/dev/null)
        if [ -n "$driver" ] && [ "$drv" != "$driver" ]; then
            echo "Error: network '$net_name' exists with driver '$drv' (expected '$driver')." >&2
            return 1
        fi
        if [ "$attachable" = "true" ]; then
            att=$(docker network inspect -f '{{.Attachable}}' "$net_name" 2>/dev/null)
            if [ "$att" != "true" ]; then
                echo "Enabling attachable on existing network '$net_name'..."
                if ! docker network update --attachable "$net_name" >/dev/null 2>&1; then
                    echo "Error: failed to enable attachable on network '$net_name'." >&2
                    return 1
                fi
            fi
        fi
    else
        create_args="--driver $driver"
        if [ "$attachable" = "true" ]; then
            create_args="$create_args --attachable"
        fi
        echo "Creating network '$net_name' ($create_args)..."
        if ! docker network create $create_args "$net_name" >/dev/null 2>&1; then
            echo "Error: failed to create network '$net_name'." >&2
            return 1
        fi
    fi
    
    echo "Waiting for network '$net_name' to be visible (timeout: ${timeout}s)..."
    i=0
    while [ "$i" -lt "$attempts" ]; do
        if docker network inspect "$net_name" >/dev/null 2>&1 &&
        docker network ls --format '{{.Name}}' 2>/dev/null | grep -Fxq "$net_name"; then
            echo "Network '$net_name' is present and visible."
            return 0
        fi
        sleep "$interval"
        i=$((i + 1))
    done
    
    echo "Warning: timed out waiting for network '$net_name' to be visible after ${timeout}s." >&2
    return 2
}

cleanup_exited_containers() {
    echo "Cleaning up exited containers..."
    if docker ps -aq -f status=exited | grep -q .; then
        docker rm $(docker ps -aq -f status=exited) >/dev/null 2>&1 || true
        echo "Removed exited containers."
    else
        echo "No exited containers to remove."
    fi
}

# Build an image and verify it exists; all config passed as parameters.
# Usage:
#   build_and_verify_image "/path/to/Dockerfile" "repo/name" "tag" "/build/context" 300 1
build_and_verify_image() {
    dockerfile_path="$1"    # e.g., "${SCRIPT_DIR}/Dockerfile"
    image_name="$2"         # e.g., "python-mcp"
    tag="${3:-latest}"      # e.g., "latest"
    context="${4:-.}"       # e.g., "${ROOT_DIR}"
    timeout="${5:-300}"     # seconds
    interval="${6:-1}"      # seconds
    
    if [ -z "$dockerfile_path" ] || [ -z "$image_name" ]; then
        echo "Error: function utils.sh:build_and_verify_image requires dockerfile path and image name." >&2
        return 1
    fi
    
    if [ ! -f "$dockerfile_path" ]; then
        echo "Error: Dockerfile '$dockerfile_path' not found." >&2
        return 1
    fi
    
    full_ref="${image_name}:${tag}"
    echo "Building image '$full_ref' from Dockerfile '$dockerfile_path' with context '$context'..."
    if ! docker build -f "$dockerfile_path" -t "$full_ref" "$context"; then
        echo "Error: failed to build image '$full_ref'." >&2
        return 1
    fi
    
    echo "Checking if image '$full_ref' was built..."
    attempts=$(( (timeout + interval - 1) / interval ))
    i=0
    while [ "$i" -lt "$attempts" ]; do
        if docker image inspect "$full_ref" >/dev/null 2>&1; then
            echo "Image '$full_ref' build completed and verified."
            return 0
        fi
        echo "Image '$full_ref' not found, waiting..."
        sleep "$interval"
        i=$((i + 1))
    done
    
    echo "Warning: timed out waiting for image '$full_ref' to be visible after ${timeout}s." >&2
    return 2
}

deploy_and_verify_stack() {
    stack="$1"
    compose="$2"
    max_wait="${3:-300}"
    interval=5

    if [ -z "$stack" ] || [ -z "$compose" ]; then
        echo "Usage: deploy_and_verify_stack STACK_NAME COMPOSE_FILE [TIMEOUT_SECONDS]" >&2
        return 2
    fi

    if ! docker stack deploy -c "$compose" "$stack"; then
        echo "Deploy failed: $stack" >&2
        return 1
    fi

    waited=0
    ready=0
    while [ "$waited" -lt "$max_wait" ]; do
        services="$(docker stack services --format '{{.Name}} {{.Replicas}}' "$stack" 2>/dev/null)"
        if [ -n "$services" ]; then
            ready="$(printf '%s\n' "$services" | awk '{split($2,a,"/"); t++; if (a[1]==a[2] && a[2]>0) r++} END {print (t>0 && r==t)?1:0}')"
            [ "$ready" -eq 1 ] && break
        fi
        sleep "$interval"
        waited=$((waited + interval))
    done

    if [ "$ready" -ne 1 ]; then
        echo "Stack not ready within ${max_wait}s: $stack" >&2
        docker stack services "$stack" || true
        return 3
    fi

    echo "Stack is running: $stack"
    docker stack services "$stack"
}
