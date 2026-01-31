#!/usr/bin/env bash
set -euo pipefail

# Load common library
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_common_vars
cd "$REPO_ROOT"

# Use both base and obfs4 compose files
COMPOSE_BASE="${COMPOSE_BASE:-$REPO_ROOT/compose/compose.yml}"
COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.obfs4.yml}"
COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_BASE -f $COMPOSE_OVERRIDE"

OBFS4_PORT="${OBFS4_PORT:-12345}"

TS="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
RUN_DIR="$REPO_ROOT/results/runs/obfs4/$TS"
PCAP_FILE="$RUN_DIR/wg-obfs4.pcap"

mkdir -p "$RUN_DIR" "$SURICATA_LOG_DIR"
check_docker

start_stack "$COMPOSE_FLAGS"
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

log "Run directory: $RUN_DIR"
log "OBFS4: WireGuard traffic wrapped in obfs4 protocol"

reset_suricata_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

# --- Wait for obfuscation proxies to be ready ---
log "Waiting for OBFS4 tunnels to initialize..."
sleep 3

# --- Capture traffic (TCP and UDP) ---
start_tcpdump "$BRIDGE_IF" "port ${OBFS4_PORT}" "$PCAP_FILE"

generate_traffic "$CLIENT_CONTAINER" "$TARGET_IP" "$TARGET_PORT" "$HTTP_REQUESTS"

sleep "$TCPDUMP_SECONDS_TAIL"
stop_tcpdump "$TCPDUMP_PID"

collect_artifacts "$RUN_DIR" "$PCAP_FILE"
log "Done."
