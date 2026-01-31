#!/usr/bin/env bash
set -euo pipefail

# Load common library
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_common_vars
cd "$REPO_ROOT"

# Use both base and udp2raw compose files
COMPOSE_BASE="${COMPOSE_BASE:-$REPO_ROOT/compose/compose.yml}"
COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.udp2raw.yml}"
COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_BASE -f $COMPOSE_OVERRIDE"

TS="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
RUN_DIR="$REPO_ROOT/results/runs/udp2raw/$TS"
PCAP_FILE="$RUN_DIR/wg-udp2raw.pcap"

mkdir -p "$RUN_DIR" "$SURICATA_LOG_DIR"
check_docker

start_stack "$COMPOSE_FLAGS"
# NOTE: udp2raw scenario also uses sniffing on "client_net" by default (same as baseline)
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

log "Run directory: $RUN_DIR"
log "UDP2RAW: WireGuard traffic wrapped in TCP/443"

reset_suricata_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

# --- Wait for obfuscation proxies to be ready ---
log "Waiting for UDP2RAW tunnels to initialize..."
sleep 3

# --- Capture traffic ---
start_tcpdump "$BRIDGE_IF" "tcp port 443" "$PCAP_FILE"

generate_traffic "$CLIENT_CONTAINER" "$TARGET_IP" "$TARGET_PORT" "$HTTP_REQUESTS"

sleep "$TCPDUMP_SECONDS_TAIL"
stop_tcpdump "$TCPDUMP_PID"

collect_artifacts "$RUN_DIR" "$PCAP_FILE"
log "Done."
