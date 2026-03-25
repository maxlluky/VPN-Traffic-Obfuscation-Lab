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

# Print a progress bar in-place (overwrites current line).
# Uses ANSI escape \033[2K to clear the entire line before printing,
# preventing artifacts from previous longer lines or interleaved output.
# Bar width is 30 chars to stay well under 80-column terminals.
# Usage: print_progress "label" current total
print_progress() {
    local label="$1"
    local current="$2"
    local total="$3"

    local perc=0
    if [ "$total" -gt 0 ]; then
        perc=$((current * 100 / total))
    fi
    # Clamp to 0-100
    [ "$perc" -gt 100 ] && perc=100
    [ "$perc" -lt 0 ]   && perc=0

    local filled=$((perc * 30 / 100))
    local bar=""
    if [ "$filled" -gt 0 ]; then
        bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    fi
    printf "\033[2K\r[*] %s: [%-30s] %d/%d (%d%%)" "$label" "$bar" "$current" "$total" "$perc"
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
    NDPI_LOG_DIR="$REPO_ROOT/results/ndpi-results"
    FAST_LOG="$SURICATA_LOG_DIR/fast.log"
    EVE_LOG="$SURICATA_LOG_DIR/eve.json"

    mkdir -p "$SURICATA_LOG_DIR" "$ZEEK_LOG_DIR" "$NDPI_LOG_DIR"
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

    TARGET_IP="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$EXT_NET_NAME\"}}{{.IPAddress}}{{end}}" "$target_container" 2>/dev/null || true)"
    [[ -n "$TARGET_IP" ]] || die "Could not resolve target IP for '$target_container' on external_net."
    log "Target: $target_container => $TARGET_IP:$TARGET_PORT"

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

    log "Resetting Suricata, Zeek & nDPI logs..."
    sudo -v
    sudo sh -lc " : > '$FAST_LOG' ; : > '$EVE_LOG' "
    sudo rm -f "$ZEEK_LOG_DIR"/*.log
    sudo rm -f "$NDPI_LOG_DIR"/*.csv "$NDPI_LOG_DIR"/*.txt "$NDPI_LOG_DIR"/*.json

    log "Recreating detection services (BRIDGE_IF=$bridge_if)..."
    BRIDGE_IF="$bridge_if" docker compose $compose_flags up -d --force-recreate --no-deps suricata zeek ndpi

    # Wait for Suricata engine to fully initialise (rule parsing + capture ready)
    wait_for_suricata

    # Brief wait for nDPI to attach to the interface (typically <1s)
    log "Waiting for nDPI to start capturing..."
    local ndpi_wait=10
    for i in $(seq 1 "$ndpi_wait"); do
        if docker logs ndpi-dpi 2>&1 | grep -qi "Starting ndpiReader"; then
            log "nDPI ready after ${i}s."
            break
        fi
        sleep 1
    done
}

wait_for_suricata() {
    local max_wait=60
    log "Waiting for Suricata engine to start (loading ET Open rules)..."
    for i in $(seq 1 "$max_wait"); do
        if docker logs suricata-ids 2>&1 | grep -qi "engine started"; then
            log "Suricata engine ready after ${i}s."
            return 0
        fi
        sleep 1
    done
    log "WARNING: Suricata did not report 'engine started' within ${max_wait}s. Proceeding anyway."
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
    local run_dir="$5"

    STREAM_DURATION="${STREAM_DURATION:-60}"
    SEED="${SEED:-$(date +%s)}"
    export SEED

    log "Generating traffic (Mode: $TRAFFIC_MODE, Seed: $SEED)..."

    if [ "$TRAFFIC_MODE" = "streaming" ]; then
        log "Streaming mode: Running iperf3 for ${STREAM_DURATION}s..."
        mkdir -p "$run_dir/iperf"
        local iperf_out="$run_dir/iperf/iperf.json"

        # Background iperf3; redirect stdout to file, suppress stderr
        docker exec "$client_container" iperf3 -c "$target_ip" -t "$STREAM_DURATION" -J \
            > "$iperf_out" 2>/dev/null &
        local iperf_pid=$!

        # Progress bar (time-based)
        local i
        for i in $(seq 1 "$STREAM_DURATION"); do
            print_progress "Streaming" "$i" "$STREAM_DURATION"
            sleep 1
        done
        echo ""
        wait "$iperf_pid" 2>/dev/null || log "WARNING: iperf3 exited with non-zero status."
    else
        log "Burst mode: $count requests (Python generator)..."
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

    log "Collecting artifacts..."

    # ── Get tool versions BEFORE stopping containers ──────────
    local suricata_ver="Unknown"
    if docker ps -q -f name=suricata-ids | grep -q .; then
        suricata_ver=$(docker exec suricata-ids suricata -V 2>/dev/null | head -n 1)
    fi
    local zeek_ver="Unknown"
    if docker ps -q -f name=zeek-nsm | grep -q .; then
        zeek_ver=$(docker exec zeek-nsm zeek --version 2>/dev/null | head -n 1)
    fi
    local ndpi_ver="Unknown"
    if [ -f "$NDPI_LOG_DIR/ndpi_meta.json" ]; then
        ndpi_ver=$(sed -n 's/.*"ndpi_version": *"\([^"]*\)".*/\1/p' "$NDPI_LOG_DIR/ndpi_meta.json")
        [ -z "$ndpi_ver" ] && ndpi_ver="Unknown"
    fi

    # ── Stop detection services to flush logs ─────────────────
    log "Stopping Suricata, Zeek & nDPI to flush logs..."
    docker stop suricata-ids >/dev/null 2>&1 || true
    docker stop zeek-nsm    >/dev/null 2>&1 || true
    docker stop ndpi-dpi    >/dev/null 2>&1 || true
    sleep 5

    # ── Create directory structure ────────────────────────────
    mkdir -p "$run_dir/pcap" "$run_dir/suricata" "$run_dir/zeek" "$run_dir/ndpi" "$run_dir/pcap_features"

    # ── Move PCAP ─────────────────────────────────────────────
    if [ -f "$pcap_file" ]; then
        mv "$pcap_file" "$run_dir/pcap/"
    fi
    if [ -f "${pcap_file}.log" ]; then
        mv "${pcap_file}.log" "$run_dir/pcap/"
    fi

    # ── Copy detection service logs ───────────────────────────
    sudo cp "$FAST_LOG" "$run_dir/suricata/fast.log" 2>/dev/null || true
    sudo cp "$EVE_LOG"  "$run_dir/suricata/eve.json" 2>/dev/null || true
    if [ -f "$SURICATA_LOG_DIR/suricata_meta.json" ]; then
        sudo cp "$SURICATA_LOG_DIR/suricata_meta.json" "$run_dir/suricata/metadata.json"
    fi
    sudo cp "$ZEEK_LOG_DIR"/*.log "$run_dir/zeek/" 2>/dev/null || true
    sudo cp "$NDPI_LOG_DIR"/flows.csv  "$run_dir/ndpi/" 2>/dev/null || true
    sudo cp "$NDPI_LOG_DIR"/summary.txt "$run_dir/ndpi/" 2>/dev/null || true

    # ── Parse nDPI detected protocol ──────────────────────────
    local ndpi_proto="N/A"
    if [ -f "$run_dir/ndpi/summary.txt" ]; then
        ndpi_proto=$(grep -A 1 "Detected protocols:" "$run_dir/ndpi/summary.txt" | tail -1 | awk '{print $1}')
        [ -z "$ndpi_proto" ] && ndpi_proto="N/A"
        log "nDPI result: $ndpi_proto"
    fi

    # ── PCAP Feature Extraction ───────────────────────────────
    local pcap_path="$run_dir/pcap/$(basename "$pcap_file")"
    local packet_csv="$run_dir/pcap_features/packets.csv"

    if [ -f "$pcap_path" ]; then
        extract_packet_features "$pcap_path" "$packet_csv"
    else
        log "WARNING: No PCAP found for feature extraction."
    fi

    # ── Generate metadata LAST (after all data is available) ──
    local tshark_ver
    tshark_ver=$(tshark --version 2>/dev/null | head -n 1 | sed 's/Running on.*//')

    local run_timestamp
    run_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat <<EOF > "$run_dir/metadata.json"
{
  "timestamp": "$run_timestamp",
  "seed": "$SEED",
  "mode": "$TRAFFIC_MODE",
  "scenario": "${SCENARIO:-unknown}",
  "ndpi_protocol": "$ndpi_proto",
  "versions": {
    "suricata": "$suricata_ver",
    "zeek": "$zeek_ver",
    "tshark": "$tshark_ver",
    "ndpi": "$ndpi_ver"
  }
}
EOF

    log "Artifacts saved to $run_dir"
    ls -R "$run_dir" | sed 's/^/    /'
}

#######################################
# PCAP Feature Extraction (with progress bar)
#######################################
extract_packet_features() {
    local pcap_path="$1"
    local packet_csv="$2"

    # Count total packets — prefer capinfos (reads header only, milliseconds)
    # with tshark fallback (must read entire PCAP)
    local total_pkts=0
    if command -v capinfos >/dev/null 2>&1; then
        total_pkts=$(capinfos -c -M "$pcap_path" 2>/dev/null | awk -F': +' '/Number of packets/{print $2}')
    fi
    if [ -z "$total_pkts" ] || [ "$total_pkts" -eq 0 ] 2>/dev/null; then
        total_pkts=$(tshark -r "$pcap_path" -T fields -e frame.number 2>/dev/null | wc -l)
    fi

    log "Extracting packet features ($total_pkts packets)..."

    if [ "$total_pkts" -le 0 ] 2>/dev/null; then
        log "WARNING: PCAP contains 0 packets, skipping extraction."
        return 0
    fi

    # Run tshark extraction in background; suppress script's own echo output
    # (tshark writes to $packet_csv via its own redirect, so >/dev/null is safe)
    "$REPO_ROOT/scripts/pcap_to_packet_csv.sh" "$pcap_path" "$packet_csv" >/dev/null 2>&1 &
    local tshark_pid=$!

    # Monitor output file line count as progress
    local current=0
    while kill -0 "$tshark_pid" 2>/dev/null; do
        if [ -f "$packet_csv" ]; then
            current=$(wc -l < "$packet_csv" 2>/dev/null || echo 0)
            # Subtract 1 for CSV header line
            current=$((current > 0 ? current - 1 : 0))
            print_progress "Packets" "$current" "$total_pkts"
        fi
        sleep 0.5
    done

    # Final state
    wait "$tshark_pid" 2>/dev/null || true
    if [ -f "$packet_csv" ]; then
        current=$(wc -l < "$packet_csv" 2>/dev/null || echo 0)
        current=$((current > 0 ? current - 1 : 0))
    fi
    print_progress "Packets" "$current" "$total_pkts"
    echo ""
}
