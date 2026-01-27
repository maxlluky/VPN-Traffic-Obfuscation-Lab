#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# run_baseline.sh
#
# Purpose:
#   Execute one reproducible baseline experiment run:
#   - Start baseline docker compose stack
#   - Determine the correct Docker bridge interface for client_net
#   - Recreate Suricata sensor to sniff on that bridge
#   - Clear Suricata output logs for a clean run
#   - Capture encrypted WireGuard UDP traffic (port 51820) on the bridge
#   - Automatically resolve the target container IP
#   - Generate HTTP traffic through the VPN tunnel to the target
#   - Save artefacts (pcap + Suricata logs) into a timestamped run directory
#
# Artefacts created:
#   ~/vpn-lab/results/runs/baseline/<DD-MM-YYYY-HH-MM>/
#     - wg-baseline.pcap
#     - fast.log
#     - eve.json
###############################################################################

# ---- Configuration ----------------------------------------------------------
COMPOSE_FILE="$HOME/vpn-lab/compose/baseline.yml"
NET_NAME="vpn-lab-baseline_client_net"

TARGET_CONTAINER="target-server"
TARGET_PORT="80"
HTTP_REQUESTS=50
TCPDUMP_SECONDS_TAIL=2

# UTC timestamp
TS="$(date -u +"%d-%m-%Y-%H-%M")"
RUN_DIR="$HOME/vpn-lab/results/runs/baseline/${TS}"

# Suricata log files (host path)
SURICATA_LOG_DIR="$HOME/vpn-lab/results/suricata-alerts"
FAST_LOG="$SURICATA_LOG_DIR/fast.log"
EVE_LOG="$SURICATA_LOG_DIR/eve.json"

mkdir -p "$RUN_DIR"

# ---- Helper functions -------------------------------------------------------
log() { echo "[*] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

# Ensure docker is usable (avoid confusing failures later)
docker ps >/dev/null 2>&1 || die "Docker daemon not accessible. Does 'docker ps' work without sudo?"

# ---- Start stack ------------------------------------------------------------
log "Starting baseline stack..."
cd "$HOME/vpn-lab/compose"
docker compose -f "$COMPOSE_FILE" up -d --build

# ---- Resolve dynamic interfaces / IPs ---------------------------------------
# Bridge interface for client_net (changes after down/up)
BRIDGE_IF="br-$(docker network inspect "$NET_NAME" --format '{{.Id}}' | cut -c1-12)"

# Resolve target container IP (always use external_net IP in your topology)
# We prefer external_net (vpn-lab-baseline_external_net) if present.
TARGET_IP="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "vpn-lab-baseline_external_net"}}{{$v.IPAddress}}{{end}}{{end}}' "$TARGET_CONTAINER" 2>/dev/null || true)"
if [[ -z "$TARGET_IP" ]]; then
  # Fallback: first available network IP
  TARGET_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$TARGET_CONTAINER" 2>/dev/null || true)"
fi
[[ -n "$TARGET_IP" ]] || die "Could not resolve IP address for container '$TARGET_CONTAINER'. Is it running?"

PCAP_FILE="$RUN_DIR/wg-baseline.pcap"

log "Run directory: $RUN_DIR"
log "Client network: $NET_NAME"
log "Bridge interface: $BRIDGE_IF"
log "Target container: $TARGET_CONTAINER"
log "Target IP: $TARGET_IP:$TARGET_PORT"

# ---- Ensure Suricata sniffs the correct interface ---------------------------
log "Recreating Suricata sensor to sniff on $BRIDGE_IF..."
BRIDGE_IF="$BRIDGE_IF" docker compose -f "$COMPOSE_FILE" up -d --force-recreate suricata

# ---- Prepare clean Suricata logs for this run -------------------------------
log "Resetting Suricata logs (fast.log, eve.json)..."
sudo mkdir -p "$SURICATA_LOG_DIR"
sudo sh -lc " : > '$FAST_LOG' ; : > '$EVE_LOG' "

# ---- Start tcpdump capture (background) -------------------------------------
# IMPORTANT: Capture must run while traffic is generated, otherwise PCAP can be empty.
log "Starting tcpdump capture (encrypted WireGuard UDP/51820) -> $PCAP_FILE"
sudo -v

sudo tcpdump -ni "$BRIDGE_IF" udp port 51820 -w "$PCAP_FILE" >/dev/null 2>&1 &
TCPDUMP_PID=$!

# Give tcpdump a moment to attach
sleep 1

# ---- Generate traffic through the tunnel ------------------------------------
log "Generating HTTP traffic through the tunnel (${HTTP_REQUESTS} requests)..."
for i in $(seq 1 "$HTTP_REQUESTS"); do
  docker exec -it client-node sh -lc "curl -s --max-time 5 http://$TARGET_IP:$TARGET_PORT/ >/dev/null" || true
done

# Capture a little tail (keepalives/responses)
sleep "$TCPDUMP_SECONDS_TAIL"

# ---- Stop tcpdump cleanly ---------------------------------------------------
log "Stopping tcpdump..."
sudo kill -2 "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

# ---- Copy Suricata logs to run directory ------------------------------------
log "Copying Suricata logs into run directory..."
if cp "$FAST_LOG" "$RUN_DIR/fast.log" 2>/dev/null; then :; else sudo cp "$FAST_LOG" "$RUN_DIR/fast.log"; fi
if cp "$EVE_LOG"  "$RUN_DIR/eve.json"  2>/dev/null; then :; else sudo cp "$EVE_LOG"  "$RUN_DIR/eve.json";  fi

# ---- Quick sanity output -----------------------------------------------------
log "Artefacts created:"
ls -lah "$RUN_DIR" | sed 's/^/    /'

log "Sanity checks (bytes):"
( sudo wc -c "$PCAP_FILE" "$RUN_DIR/eve.json" "$RUN_DIR/fast.log" 2>/dev/null || true ) | sed 's/^/    /'

log "Done."