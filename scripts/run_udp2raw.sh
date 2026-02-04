#!/usr/bin/env bash
set -euo pipefail

# Load common library
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_common_vars

# Specific Config
SCENARIO="udp2raw"
SNIFF_KEY="${SNIFF_KEY:-client_net}"
TS="$(date -u +"%d-%m-%Y-%H-%M-%S")"
RUN_DIR="$REPO_ROOT/results/runs/udp2raw/$TS"
PCAP_FILE="$RUN_DIR/wg-udp2raw.pcap"

mkdir -p "$RUN_DIR"
echo "{\"traffic_mode\": \"${TRAFFIC_MODE:-burst}\"}" > "$RUN_DIR/run_info.json"
check_docker

COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.udp2raw.yml}"
COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_BASE -f $COMPOSE_OVERRIDE"

log "Run directory: $RUN_DIR"
log "UDP2RAW: WireGuard traffic wrapped in TCP/443"

start_stack "$COMPOSE_FLAGS"
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

reset_ids_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

log "Waiting for UDP2RAW tunnels to initialize..."
sleep 3

# Capture TCP/443
start_tcpdump "$BRIDGE_IF" "tcp port 443" "$PCAP_FILE"

generate_traffic "$CLIENT_CONTAINER" "$TARGET_IP" "$TARGET_PORT" "$HTTP_REQUESTS"

sleep "$TCPDUMP_SECONDS_TAIL"
stop_tcpdump "$TCPDUMP_PID"

collect_artifacts "$RUN_DIR" "$PCAP_FILE"

log "Done."
