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
    SEED="${SEED:-$(date +%s)}" # Default seed if not set
    
    export SEED # Export for other functions if needed
    
    log "Generating traffic (Mode: $TRAFFIC_MODE, Seed: $SEED)..."

    if [ "$TRAFFIC_MODE" == "streaming" ]; then
        log "Streaming mode: Running iperf3 for $STREAM_DURATION seconds..."
        
        # Run iperf3 client with JSON output
        if ! docker exec "$client_container" iperf3 -c "$target_ip" -t "$STREAM_DURATION" -J > iperf_output.json 2>/dev/null & then
             IPERF_PID=$!
             
             # Progress bar
             for i in $(seq 1 "$STREAM_DURATION"); do
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
        # Burst Mode via Python Script
        log "Burst mode: $count requests (Python generator)..."
        
        # We assume traffic_gen.py is at /usr/local/bin/traffic_gen.py
        docker exec "$client_container" python3 -u /usr/local/bin/traffic_gen.py \
            --target "http://$target_ip:$target_port" \
            --count "$count" \
            --seed "$SEED" \
            --delay-min 0.1 --delay-max 2.0 || die "Traffic generation failed."
    fi
    
    echo ""
}

#######################################
# Artifact Collection
#######################################
collect_artifacts() {
    local run_dir="$1"
    local pcap_file="$2"
    
    log "Organizing artifacts..."

    # Flushing Zeek logs
    log "Stopping Zeek to flush logs..."
    docker stop zeek-nsm >/dev/null 2>&1 || true
    sleep 5
    
    # Create subdirectories
    mkdir -p "$run_dir/pcap" "$run_dir/suricata" "$run_dir/zeek" "$run_dir/pcap_features"
    
    # Move PCAP
    if [ -f "$pcap_file" ]; then
        mv "$pcap_file" "$run_dir/pcap/"
    fi
    # If tcpdump produced .log (stderr), move it too
    if [ -f "${pcap_file}.log" ]; then
        mv "${pcap_file}.log" "$run_dir/pcap/"
    fi

    # Copy Suricata logs (fast.log, eve.json)
    sudo cp "$FAST_LOG" "$run_dir/suricata/fast.log" 2>/dev/null || true
    sudo cp "$EVE_LOG"  "$run_dir/suricata/eve.json" 2>/dev/null || true
    # Copy Suricata metadata if it exists (from volume map)
    # We mapped ../results/suricata-alerts:/var/log/suricata
    if [ -f "$SURICATA_LOG_DIR/suricata_meta.json" ]; then
        sudo cp "$SURICATA_LOG_DIR/suricata_meta.json" "$run_dir/suricata/metadata.json"
    fi
    
    # Copy Zeek logs
    sudo cp "$ZEEK_LOG_DIR"/*.log "$run_dir/zeek/" 2>/dev/null || true
    
    # Move iperf output if exists
    # Move iperf output if exists
    if [ -f "iperf_output.json" ]; then
        mkdir -p "$run_dir/iperf"
        mv "iperf_output.json" "$run_dir/iperf/iperf.json"
    fi

    # ---------------------------------------------------------
    # Generate Run Metadata
    # ---------------------------------------------------------
    log "Generating Metadata..."
    
    # Get Tool Versions
    # Suricata (from container if possible, or assume generic if already down, but we just stopped zeek, suricata might be up)
    # Actually, we can get it from the suricata_meta.json if we captured it.
    # Otherwise try docker exec.
    SURICATA_VER="Unknown"
    if docker ps -q -f name=suricata-ids | grep -q .; then
        SURICATA_VER=$(docker exec suricata-ids suricata -V 2>/dev/null | head -n 1)
    fi

    ZEEK_VER="Unknown"
    # Zeek container is stopped above. We should have captured it before or restart/run just for version? 
    # Or just use the image tag. 
    # Let's rely on `zeek --version` via temporary container or assume "zeek" command availability?
    # Better: Start a temp container to get version or check if we can get it from logs.
    # `docker run --rm ${ZEEK_IMAGE} zeek --version` might work if variable available.
    # For now, let's try to get it from the stopped container logs or start it briefly? 
    # Actually, let's just run a quick check command.
    ZEEK_VER=$(docker run --rm --entrypoint zeek "${ZEEK_IMAGE:-zeek/zeek:latest}" --version 2>/dev/null | head -n 1)

    TSHARK_VER=$(tshark --version 2>/dev/null | head -n 1 | sed 's/Running on.*//')
    
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    cat <<EOF > "$run_dir/metadata.json"
{
  "timestamp": "$TIMESTAMP",
  "seed": "$SEED",
  "mode": "$TRAFFIC_MODE",
  "scenario": "${SCENARIO:-unknown}",
  "versions": {
    "suricata": "$SURICATA_VER",
    "zeek": "$ZEEK_VER",
    "tshark": "$TSHARK_VER"
  }
}
EOF

    # ---------------------------------------------------------
    # PCAP Feature Extraction
    # ---------------------------------------------------------
    local packet_csv="$run_dir/pcap_features/packets.csv"
    local pcap_path="$run_dir/pcap/$(basename "$pcap_file")"
    
    if [ -f "$pcap_path" ]; then
        log "Extracting Packet Features to $packet_csv..."
        # Call extraction script
        "$REPO_ROOT/scripts/pcap_to_packet_csv.sh" "$pcap_path" "$packet_csv"
    else
        log "WARNING: No PCAP found for extraction."
    fi

    log "Artifacts created in $run_dir:"
    ls -R "$run_dir" | sed 's/^/    /'
}
