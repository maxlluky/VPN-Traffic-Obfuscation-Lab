#!/usr/bin/env bash
set -euo pipefail

# Load common library
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_common_vars

# Specific Config
SNIFF_KEY="${SNIFF_KEY:-client_net}"
TS="$(date -u +"%d-%m-%Y-%H-%M-%S")"
RUN_DIR="$REPO_ROOT/results/runs/obfs4/$TS"
PCAP_FILE="$RUN_DIR/wg-obfs4.pcap"

mkdir -p "$RUN_DIR"
check_docker

COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.obfs4.yml}"
COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_BASE -f $COMPOSE_OVERRIDE"

OBFS4_PORT="${OBFS4_PORT:-12345}"

log "Run directory: $RUN_DIR"
log "OBFS4: WireGuard traffic wrapped in obfs4 protocol"

start_stack "$COMPOSE_FLAGS"
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

reset_ids_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

log "Waiting for OBFS4 tunnels to initialize..."
sleep 3

# Capture traffic (TCP and UDP on port 12345)
# Using 'port' to catch both just in case, though obfs4 normally runs on a specific protocol. 
# We found it runs UDP-based Obfs4 in this setup.
start_tcpdump "$BRIDGE_IF" "port ${OBFS4_PORT}" "$PCAP_FILE"

generate_traffic "$CLIENT_CONTAINER" "$TARGET_IP" "$TARGET_PORT" "$HTTP_REQUESTS"

sleep "$TCPDUMP_SECONDS_TAIL"
stop_tcpdump "$TCPDUMP_PID"

collect_artifacts "$RUN_DIR" "$PCAP_FILE"

log "Done."
