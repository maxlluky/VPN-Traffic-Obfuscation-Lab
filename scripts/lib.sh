#!/usr/bin/env bash
# scripts/lib.sh
# Common functions for VPN Traffic Obfuscation Lab scripts

set -euo pipefail

# --- Logging ---
log() { echo "[*] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

# --- Constants & Defaults ---
setup_common_vars() {
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # These can be overridden by environment
    SNIFF_KEY="${SNIFF_KEY:-client_net}"
    TARGET_CONTAINER="${TARGET_CONTAINER:-target-server}"
    CLIENT_CONTAINER="${CLIENT_CONTAINER:-client-node}"
    TARGET_PORT="${TARGET_PORT:-80}"
    HTTP_REQUESTS="${HTTP_REQUESTS:-50}"
    TCPDUMP_SECONDS_TAIL="${TCPDUMP_SECONDS_TAIL:-2}"
    
    SURICATA_LOG_DIR="$REPO_ROOT/results/suricata-alerts"
    FAST_LOG="$SURICATA_LOG_DIR/fast.log"
    EVE_LOG="$SURICATA_LOG_DIR/eve.json"
}

# --- Infrastructure Setup ---
check_docker() {
    docker ps >/dev/null 2>&1 || die "Docker daemon not accessible."
}

start_stack() {
    local compose_flags="$1"
    log "Starting stack..."
    # Ensure clean slate
    docker compose $compose_flags down --remove-orphans >/dev/null 2>&1 || true
    docker compose $compose_flags up -d --build --remove-orphans
}

# --- Network Discovery ---
detect_network_info() {
    local target_container="$1"
    local sniff_key="$2"
    
    # 1. Get Project Name
    PROJECT="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$target_container" 2>/dev/null || true)"
    [[ -n "$PROJECT" ]] || die "Could not determine compose project from '$target_container'. Is the stack up?"
    log "Compose project: $PROJECT"
    log "Sniff network key: $sniff_key"

    # 2. Find Network ID
    NET_ID="$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.network=$sniff_key" | head -n 1)"
    [[ -n "$NET_ID" ]] || die "Could not find network for project=$PROJECT and network=$sniff_key."

    # 3. Resolve Bridge Interface
    BRIDGE_IF="$(docker network inspect "$NET_ID" -f '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)"
    if [[ -z "${BRIDGE_IF:-}" || "$BRIDGE_IF" == "<no value>" ]]; then
        BRIDGE_IF="br-${NET_ID:0:12}"
    fi

    check_bridge_interface "$BRIDGE_IF" "$NET_ID"
    
    # 4. Resolve Target IP (on external_net)
    EXT_NET_ID="$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.network=external_net" | head -n 1)"
    [[ -n "$EXT_NET_ID" ]] || die "Could not find external_net for project=$PROJECT."
    EXT_NET_NAME="$(docker network inspect "$EXT_NET_ID" -f '{{.Name}}')"

    TARGET_IP="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$EXT_NET_NAME\"}}{{.IPAddress}}{{end}}" "$target_container" 2>/dev/null || true)"
    [[ -n "$TARGET_IP" ]] || die "Could not resolve target IP for '$target_container' on external_net."

    log "Bridge IF: $BRIDGE_IF"
    log "Target: $target_container => $TARGET_IP:$TARGET_PORT"
}

check_bridge_interface() {
    local iface="$1"
    local net_id="$2"
    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "[!] Bridge interface '$iface' not found on host."
        echo "[!] Available bridges:"
        ip -br link | awk '$1 ~ /^br-|^docker0/ {print "    " $0}'
        die "Could not resolve a valid bridge interface for network id $net_id."
    fi
}

# --- Logs & Capture ---

reset_suricata_logs() {
    local bridge_if="$1"
    local compose_flags="$2"
    
    log "Resetting Suricata logs..."
    sudo -v
    sudo sh -lc " : > '$FAST_LOG' ; : > '$EVE_LOG' "

    log "Recreating Suricata (BRIDGE_IF=$bridge_if)..."
    BRIDGE_IF="$bridge_if" docker compose $compose_flags up -d --force-recreate --no-deps suricata
}

start_tcpdump() {
    local iface="$1"
    local filter="$2"
    local output="$3"
    
    log "Starting tcpdump on $iface ($filter) -> $output"
    sudo tcpdump -ni "$iface" $filter -w "$output" >/dev/null 2>&1 &
    TCPDUMP_PID=$!
    sleep 1
}

stop_tcpdump() {
    local pid="$1"
    log "Stopping tcpdump..."
    sudo kill -2 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

# --- Traffic Generation ---
generate_traffic() {
    local client_container="$1"
    local target_ip="$2"
    local target_port="$3"
    local count="$4"
    
    log "Generating HTTP traffic ($count requests)..."
    local fail_count=0
    
    for i in $(seq 1 "$count"); do
        if ! timeout 10s docker exec "$client_container" sh -lc "curl -s --max-time 5 http://$target_ip:$target_port/ >/dev/null"; then
            log "WARNING: Request $i failed or timed out."
            fail_count=$((fail_count+1))
            if [ "$fail_count" -ge 10 ]; then
                die "Aborting: 10 consecutive failures detected."
            fi
        else
            printf "."
            fail_count=0
        fi
    done
    echo ""
}

# --- Artifacts ---
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
