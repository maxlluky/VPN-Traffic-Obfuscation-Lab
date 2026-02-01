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
    ZEEK_LOG_DIR="$REPO_ROOT/results/zeek-logs"
    FAST_LOG="$SURICATA_LOG_DIR/fast.log"
    EVE_LOG="$SURICATA_LOG_DIR/eve.json"
    
    mkdir -p "$SURICATA_LOG_DIR" "$ZEEK_LOG_DIR"
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
reset_ids_logs() {
    local bridge_if="$1"
    local compose_flags="$2"
    
    log "Resetting Suricata & Zeek logs..."
    sudo -v
    sudo sh -lc " : > '$FAST_LOG' ; : > '$EVE_LOG' "
    sudo rm -f "$ZEEK_LOG_DIR"/*.log

    log "Recreating IDS services (BRIDGE_IF=$bridge_if)..."
    BRIDGE_IF="$bridge_if" docker compose $compose_flags up -d --force-recreate --no-deps suricata zeek
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
    
    # Traffic Mode Defaults
    TRAFFIC_MODE="${TRAFFIC_MODE:-burst}"   # burst | streaming
    STREAM_DURATION="${STREAM_DURATION:-60}" # seconds for streaming
    
    log "Generating traffic (Mode: $TRAFFIC_MODE)..."

    if [ "$TRAFFIC_MODE" == "streaming" ]; then
        log "Streaming mode: Running iperf3 for $STREAM_DURATION seconds..."
        
        # Run iperf3 client
        # -c target_ip: connect to target
        # -t duration: run for X seconds
        # -p 5201: default iperf3 port
        if ! docker exec "$client_container" iperf3 -c "$target_ip" -t "$STREAM_DURATION" >/dev/null & then
             IPERF_PID=$!
             
             # Progress bar
             for i in $(seq 1 "$STREAM_DURATION"); do
                 # Calculate progress
                 perc=$((i * 100 / STREAM_DURATION))
                 filled=$((perc / 2))
                 bar=$(printf "%-${filled}s" "#" | sed 's/ /#/g')
                 printf "\r[*] Streaming: [%-50s] %d/%ds (%d%%)" "$bar" "$i" "$STREAM_DURATION" "$perc"
                 sleep 1
             done
             echo ""
             wait "$IPERF_PID" 2>/dev/null || true
        else
             log "WARNING: Failed to start iperf3."
             sleep "$STREAM_DURATION"
        fi
    else
        # Burst Mode (Default)
        log "Burst mode: $count requests..."
        FAIL_COUNT=0
        for i in $(seq 1 "$count"); do
          if ! timeout 10s docker exec "$client_container" sh -lc "curl -s --max-time 5 http://$target_ip:$target_port/ >/dev/null"; then
              log "WARNING: Request $i failed or timed out."
              FAIL_COUNT=$((FAIL_COUNT+1))
              if [ "$FAIL_COUNT" -ge 10 ]; then
                die "Aborting: 10 consecutive failures detected."
              fi
          else
              # Progress bar calculation
              perc=$((i * 100 / count))
              filled=$((perc / 2))
              bar=$(printf "%-${filled}s" "#" | sed 's/ /#/g')
              printf "\r[*] Generating: [%-50s] %d/%d reqs (%d%%)" "$bar" "$i" "$count" "$perc"
              FAIL_COUNT=0
          fi
        done
        echo ""
    fi
    
    log "Waiting 5 seconds for logs to flush..."
    sleep 5
}

#######################################
# Artifact Collection
#######################################
collect_artifacts() {
    local run_dir="$1"
    local pcap_file="$2"
    
    log "Organizing artifacts..."
    
    # Create subdirectories
    mkdir -p "$run_dir/pcap" "$run_dir/suricata" "$run_dir/zeek"
    
    # Move PCAP
    if [ -f "$pcap_file" ]; then
        mv "$pcap_file" "$run_dir/pcap/"
        if [ -f "${pcap_file}.log" ]; then
            mv "${pcap_file}.log" "$run_dir/pcap/"
        fi
    fi

    # Copy Suricata logs
    sudo cp "$FAST_LOG" "$run_dir/suricata/fast.log" 2>/dev/null || cp "$FAST_LOG" "$run_dir/suricata/fast.log"
    sudo cp "$EVE_LOG"  "$run_dir/suricata/eve.json" 2>/dev/null || cp "$EVE_LOG"  "$run_dir/suricata/eve.json"
    
    # Copy Zeek logs
    sudo cp "$ZEEK_LOG_DIR"/*.log "$run_dir/zeek/" 2>/dev/null || true
    
    log "Artifacts created in $run_dir:"
    ls -R "$run_dir" | sed 's/^/    /'
}
