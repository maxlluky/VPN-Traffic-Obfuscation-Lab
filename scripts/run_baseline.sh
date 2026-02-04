#!/usr/bin/env bash
set -euo pipefail

# Load common library
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_common_vars

# Specific Config
SCENARIO="baseline"
SNIFF_KEY="${SNIFF_KEY:-client_net}"
TS="$(date -u +"%d-%m-%Y-%H-%M-%S")"
RUN_DIR="$REPO_ROOT/results/runs/baseline/$TS"
PCAP_FILE="$RUN_DIR/wg-baseline.pcap"

mkdir -p "$RUN_DIR"
echo "{\"traffic_mode\": \"${TRAFFIC_MODE:-burst}\"}" > "$RUN_DIR/run_info.json"
check_docker

COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_BASE -f $REPO_ROOT/compose/compose.baseline.yml"

log "Run directory: $RUN_DIR"

start_stack "$COMPOSE_FLAGS"
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

reset_ids_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

# Capture WG UDP/51820
start_tcpdump "$BRIDGE_IF" "udp port 51820" "$PCAP_FILE"

generate_traffic "$CLIENT_CONTAINER" "$TARGET_IP" "$TARGET_PORT" "$HTTP_REQUESTS"

sleep "$TCPDUMP_SECONDS_TAIL"
stop_tcpdump "$TCPDUMP_PID"

collect_artifacts "$RUN_DIR" "$PCAP_FILE"

log "Done."
