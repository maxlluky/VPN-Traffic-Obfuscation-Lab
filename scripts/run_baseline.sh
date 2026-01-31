#!/usr/bin/env bash
set -euo pipefail

# Load common library
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_common_vars
cd "$REPO_ROOT"

COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/compose/compose.yml}"

TS="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
RUN_DIR="$REPO_ROOT/results/runs/baseline/$TS"
PCAP_FILE="$RUN_DIR/wg-baseline.pcap"

mkdir -p "$RUN_DIR" "$SURICATA_LOG_DIR"
check_docker

# --- Specific Config ---
COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_FILE -f $REPO_ROOT/compose/compose.baseline.yml"

start_stack "$COMPOSE_FLAGS"
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

log "Run directory: $RUN_DIR"

reset_suricata_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

# Capture WG UDP/51820
start_tcpdump "$BRIDGE_IF" "udp port 51820" "$PCAP_FILE"

generate_traffic "$CLIENT_CONTAINER" "$TARGET_IP" "$TARGET_PORT" "$HTTP_REQUESTS"

sleep "$TCPDUMP_SECONDS_TAIL"
stop_tcpdump "$TCPDUMP_PID"

collect_artifacts "$RUN_DIR" "$PCAP_FILE"
log "Done."
