#!/usr/bin/env bash
# scripts/lib.sh
# Common functions for VPN Obfuscation Lab

#######################################
# Logging & Error Handling
#######################################
log() {
    echo "[*] $*"
}

die() {
    echo "[!] $*" >&2
    exit 1
}

#######################################
# Setup & Configuration
#######################################
setup_common_vars() {
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$REPO_ROOT" || die "Could not cd to REPO_ROOT"

    # Default values
    COMPOSE_BASE="${COMPOSE_BASE:-$REPO_ROOT/compose/compose.yml}"
    TARGET_CONTAINER="${TARGET_CONTAINER:-target-server}"
    CLIENT_CONTAINER="${CLIENT_CONTAINER:-client-node}"
    TARGET_PORT="${TARGET_PORT:-80}"
    HTTP_REQUESTS="${HTTP_REQUESTS:-50}"
    TCPDUMP_SECONDS_TAIL="${TCPDUMP_SECONDS_TAIL:-2}"
    
    # Logs
    SURICATA_LOG_DIR="$REPO_ROOT/results/suricata-alerts"
    FAST_LOG="$SURICATA_LOG_DIR/fast.log"
    EVE_LOG="$SURICATA_LOG_DIR/eve.json"
    
    mkdir -p "$SURICATA_LOG_DIR"
}

check_docker() {
    docker ps >/dev/null 2>&1 || die "Docker daemon not accessible."
}

#######################################
# Stack Management
#######################################
start_stack() {
    local compose_flags="$1"
    log "Starting stack..."
    # Ensure clean slate
    docker compose $compose_flags down --remove-orphans >/dev/null 2>&1 || true
    docker compose $compose_flags up -d --build --remove-orphans || die "Failed to start stack"
}

#######################################
# Network Discovery
#######################################
detect_network_info() {
    local target_container="$1"
    local sniff_net_key="$2" # e.g. "client_net"

    # Determine project name
    PROJECT="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$target_container" 2>/dev/null || true)"
    [[ -n "$PROJECT" ]] || die "Could not determine compose project from '$target_container'. Is the stack up?"
    log "Compose project: $PROJECT"
    log "Sniff network key: $sniff_net_key"

    # Find Network ID
    NET_ID="$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.network=$sniff_net_key" | head -n 1)"
    [[ -n "$NET_ID" ]] || die "Could not find network for project=$PROJECT and network=$sniff_net_key."

    # Resolve Bridge Interface
    BRIDGE_IF="$(docker network inspect "$NET_ID" -f '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)"
    if [[ -z "${BRIDGE_IF:-}" || "$BRIDGE_IF" == "<no value>" ]]; then
      BRIDGE_IF="br-${NET_ID:0:12}"
    fi

    # Validate Bridge
    if ! ip link show "$BRIDGE_IF" >/dev/null 2>&1; then
      echo "[!] Bridge interface '$BRIDGE_IF' not found on host."
      echo "[!] Available bridges:"
      ip -br link | awk '$1 ~ /^br-|^docker0/ {print "    " $0}'
      die "Could not resolve a valid bridge interface for network id $NET_ID."
    fi
    log "Bridge IF: $BRIDGE_IF"

    # Resolve Target IP (on external_net)
    EXT_NET_ID="$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.network=external_net" | head -n 1)"
    [[ -n "$EXT_NET_ID" ]] || die "Could not find external_net for project=$PROJECT."
    EXT_NET_NAME="$(docker network inspect "$EXT_NET_ID" -f '{{.Name}}')"

    TARGET_IP="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$EXT_NET_NAME\"}}{{.IPAddress}}{{end}}" "$TARGET_CONTAINER" 2>/dev/null || true)"
    [[ -n "$TARGET_IP" ]] || die "Could not resolve target IP for '$TARGET_CONTAINER' on external_net."
    log "Target: $TARGET_CONTAINER => $TARGET_IP:$TARGET_PORT"
    
    # Export for caller
    export BRIDGE_IF
    export TARGET_IP
}

#######################################
# Suricata Logic
#######################################
reset_suricata_logs() {
    local bridge_if="$1"
    local compose_flags="$2"
    
    log "Resetting Suricata logs..."
    sudo -v
    sudo sh -lc " : > '$FAST_LOG' ; : > '$EVE_LOG' "

    log "Recreating Suricata (BRIDGE_IF=$bridge_if)..."
    BRIDGE_IF="$bridge_if" docker compose $compose_flags up -d --force-recreate --no-deps suricata
}

#######################################
# Traffic Capture
#######################################
start_tcpdump() {
    local iface="$1"
    local filter="$2"
    local outfile="$3"
    
    log "Starting tcpdump on $iface ($filter) -> $outfile"
    sudo tcpdump -ni "$iface" $filter -w "$outfile" >/dev/null 2>&1 &
    TCPDUMP_PID=$!
    sleep 1
}

stop_tcpdump() {
    local pid="$1"
    log "Stopping tcpdump..."
    sudo kill -2 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

#######################################
# Traffic Generation
#######################################
generate_traffic() {
    local client_container="$1"
    local target_ip="$2"
    local target_port="$3"
    local count="$4"
    
    log "Generating HTTP traffic ($count requests)..."
    FAIL_COUNT=0
    for i in $(seq 1 "$count"); do
      if ! timeout 10s docker exec "$client_container" sh -lc "curl -s --max-time 5 http://$target_ip:$target_port/ >/dev/null"; then
          log "WARNING: Request $i failed or timed out."
          FAIL_COUNT=$((FAIL_COUNT+1))
          if [ "$FAIL_COUNT" -ge 10 ]; then
            die "Aborting: 10 consecutive failures detected."
          fi
      else
          printf "."
          FAIL_COUNT=0
      fi
    done
    echo ""
}

#######################################
# Artifact Collection
#######################################
collect_artifacts() {
    local run_dir="$1"
    local pcap_file="$2"
    
    log "Copying Suricata logs..."
    sudo cp "$FAST_LOG" "$run_dir/fast.log" 2>/dev/null || cp "$FAST_LOG" "$run_dir/fast.log"
    sudo cp "$EVE_LOG"  "$run_dir/eve.json" 2>/dev/null || cp "$EVE_LOG"  "$run_dir/eve.json"
    
    log "Artifacts created:"
    ls -lah "$run_dir" | sed 's/^/    /'
    
    log "Sanity checks (bytes):"
    ( sudo wc -c "$pcap_file" "$run_dir/eve.json" "$run_dir/fast.log" 2>/dev/null || true ) | sed 's/^/    /'
}
