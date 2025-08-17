#!/bin/bash

# stack-verify.sh
# Verifies that Docker is accessible, required networks & volumes exist,
# and that all services from simple-oauth-dev-stack.yml are running.
# Works with either a Swarm stack (preferred) or a local docker compose up.
#
# Usage:
#   ./scripts/stack-verify.sh [--stack-name NAME] [--timeout 120] [--interval 3]
# Env Overrides:
#   STACK_NAME, VERIFY_TIMEOUT, VERIFY_INTERVAL
# Exit codes:
#   0 success; 1 docker not accessible; 2 network missing; 3 volume missing;
#   4 service missing; 5 service unhealthy/not running; 6 timeout waiting.

set -euo pipefail

STACK_NAME="${STACK_NAME:-}"  # If set, attempt swarm mode checks; if empty and swarm active we'll try auto-detect
VERIFY_TIMEOUT=${VERIFY_TIMEOUT:-120}
VERIFY_INTERVAL=${VERIFY_INTERVAL:-3}
REQUIRE_HEALTH=${REQUIRE_HEALTH:-1} # If a service has a health status, require healthy
QUIET=${QUIET:-0}

EXPECTED_NETWORKS=(proxy home-net)
EXPECTED_VOLUMES=(postgresql_data openwebui_data postgresql_data_litellm vault_data)
EXPECTED_SERVICES=(postgresql keycloak python-mcp openwebui postgresql-litellm litellm openweb-to-litellm nginx-mcp vault)

print() { if [ "$QUIET" = 0 ]; then echo -e "$@"; fi }
tab() { print "\t$@"; }

# --- Arg parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-name) STACK_NAME="$2"; shift 2;;
    --timeout) VERIFY_TIMEOUT="$2"; shift 2;;
    --interval) VERIFY_INTERVAL="$2"; shift 2;;
    --quiet) QUIET=1; shift;;
    -q) QUIET=1; shift;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //' ; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 99;;
  esac
done

START_TIME=$(date +%s)

# --- Functions ---
fail() { echo "ERROR: $1" >&2; exit "${2:-1}"; }

check_timeout() {
  local now=$(date +%s)
  local elapsed=$(( now - START_TIME ))
  if (( elapsed > VERIFY_TIMEOUT )); then
    fail "Timeout (${VERIFY_TIMEOUT}s) waiting for resources" 6
  fi
}

docker_ok() {
  if ! docker info >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

swarm_mode() { docker info 2>/dev/null | grep -qi 'Swarm: active'; }

# Try to auto-detect stack name if not provided. We look for a stack where
# all (or majority) expected services appear as <stack>_<service>.
auto_detect_stack() {
  [ -n "$STACK_NAME" ] && return 0
  swarm_mode || return 0
  local stacks candidates
  stacks=$(docker stack ls --format '{{.Name}}' 2>/dev/null || true)
  [ -z "$stacks" ] && return 0
  local best_stack="" best_score=0
  for st in $stacks; do
    local score=0
    while IFS= read -r line; do :; done <<<""
    for svc in "${EXPECTED_SERVICES[@]}"; do
      if docker stack services "$st" --format '{{.Name}}' | grep -qx "${st}_${svc}"; then
        score=$((score+1))
      fi
    done
    if (( score > best_score )); then
      best_score=$score; best_stack=$st;
    fi
  done
  # Require at least half of expected services to trust auto-detection
  local threshold=$(( (${#EXPECTED_SERVICES[@]} + 1) / 2 ))
  if (( best_score >= threshold )); then
    STACK_NAME="$best_stack"
    tab "Auto-detected stack name: $STACK_NAME (matched $best_score/${#EXPECTED_SERVICES[@]} services)"
  fi
}

service_running_compose() {
  local svc="$1"
  # Accept patterns: *_<svc>_*, *_<svc>-1, *<stack>_<svc>-1
  docker ps --format '{{.Names}} {{.Status}}' | awk -v s="$svc" 'tolower($0) ~ "_" s "_" || tolower($0) ~ "_" s "-1" || tolower($0) ~ "_" s"$" {print}'
}

service_replicas_swarm() {
  local stack="$1" svc="$2"
  docker stack services "$stack" --format '{{.Name}} {{.Replicas}}' | awk -v target="$stack" -v s="$svc" '($1==target"_"s){print $2}'
}

service_id_swarm() {
  local stack="$1" svc="$2"
  docker service ls --format '{{.ID}} {{.Name}}' | awk -v n="$stack" -v s="$svc" '($2==n"_"s){print $1}' | head -n1
}

service_tasks_running() {
  local service_id="$1"
  docker service ps "$service_id" --format '{{.CurrentState}}' 2>/dev/null | grep -c '^Running' || true
}

# --- Start ---
print "Verifying Docker accessibility..."
if ! docker_ok; then
  fail "Docker not accessible (needs permissions or daemon not running)." 1
fi
tab "Docker OK"

if [ -n "$STACK_NAME" ] && ! swarm_mode; then
  tab "WARNING: STACK_NAME provided but swarm not active; falling back to container inspection."
fi

print "Checking networks: ${EXPECTED_NETWORKS[*]}"
for net in "${EXPECTED_NETWORKS[@]}"; do
  if ! docker network inspect "$net" >/dev/null 2>&1; then
    fail "Missing network: $net" 2
  fi
  tab "Network $net present"
done

print "Checking volumes: ${EXPECTED_VOLUMES[*]}"
for vol in "${EXPECTED_VOLUMES[@]}"; do
  VOL_OK=0
  DISPLAY_MATCH=""
  # 1. Exact name
  if docker volume inspect "$vol" >/dev/null 2>&1; then
    VOL_OK=1; DISPLAY_MATCH="$vol"
  fi
  # 2. stack explicit prefix if provided
  if [ $VOL_OK -eq 0 ] && [ -n "$STACK_NAME" ]; then
    if docker volume inspect "${STACK_NAME}_${vol}" >/dev/null 2>&1; then
      VOL_OK=1; DISPLAY_MATCH="${STACK_NAME}_${vol}"
    fi
  fi
  # 3. Auto-detect any single volume ending with _<vol> or _stack_<vol>
  if [ $VOL_OK -eq 0 ]; then
    CANDIDATES=$(docker volume ls -q | grep -E "(_stack)?_${vol}$" || true)
    if [ -n "$CANDIDATES" ]; then
      CNT=$(echo "$CANDIDATES" | wc -l | awk '{print $1}')
      if [ "$CNT" = "1" ]; then
        MATCH=$(echo "$CANDIDATES" | head -n1)
        if docker volume inspect "$MATCH" >/dev/null 2>&1; then
          VOL_OK=1; DISPLAY_MATCH="$MATCH"
        fi
      fi
    fi
  fi
  if [ $VOL_OK -eq 1 ]; then
    tab "Volume $vol present as ${DISPLAY_MATCH}"
  else
    ALT=""
    if [ -n "$STACK_NAME" ]; then ALT=" (also tried ${STACK_NAME}_${vol})"; fi
    fail "Missing volume: $vol${ALT}" 3
  fi
done

auto_detect_stack

print "Checking services (stack name: ${STACK_NAME:-<none>} )..."

missing_services=()
not_running=()

while true; do
  all_good=true
  missing_services=()
  not_running=()

  for svc in "${EXPECTED_SERVICES[@]}"; do
    if [ -n "$STACK_NAME" ] && swarm_mode; then
      repl=$(service_replicas_swarm "$STACK_NAME" "$svc")
      if [ -z "$repl" ]; then
        missing_services+=("$svc")
        all_good=false
        continue
      fi
      # replicas format like 1/1
      desired=${repl#*/}
      current=${repl%%/*}
      if [ "$current" != "$desired" ]; then
        not_running+=("$svc($repl)")
        all_good=false
      else
        tab "Service $svc replicas OK ($repl)"
      fi
    else
      rows=$(service_running_compose "$svc")
      if [ -z "$rows" ]; then
        missing_services+=("$svc")
        all_good=false
        continue
      fi
      if echo "$rows" | grep -qi '(unhealthy)'; then
        not_running+=("$svc(unhealthy)")
        all_good=false
      elif echo "$rows" | grep -qi 'Up'; then
        tab "Container(s) for $svc Up"
      else
        not_running+=("$svc(status_unknown)")
        all_good=false
      fi
    fi
  done

  if $all_good; then
    break
  fi
  check_timeout
  tab "Waiting for services... missing: ${missing_services[*]:-none} not_running: ${not_running[*]:-none}"
  sleep "$VERIFY_INTERVAL"
done

if [ ${#missing_services[@]} -gt 0 ]; then
  fail "Missing services after wait: ${missing_services[*]}" 4
fi
if [ ${#not_running[@]} -gt 0 ]; then
  fail "Services not running/healthy: ${not_running[*]}" 5
fi

print "All services running. SUCCESS"
exit 0
