#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# run_udp2raw.sh
# - UDP2RAW obfuscation scenario (WireGuard tunneled through TCP/443)
# - Captures traffic and Suricata alerts
###############################################################################

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Use both base and udp2raw compose files
COMPOSE_BASE="${COMPOSE_BASE:-$REPO_ROOT/compose/compose.yml}"
COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.udp2raw.yml}"

SNIFF_KEY="${SNIFF_KEY:-client_net}"

TARGET_CONTAINER="${TARGET_CONTAINER:-target-server}"
CLIENT_CONTAINER="${CLIENT_CONTAINER:-client-node}"
TARGET_PORT="${TARGET_PORT:-80}"
HTTP_REQUESTS="${HTTP_REQUESTS:-50}"
TCPDUMP_SECONDS_TAIL="${TCPDUMP_SECONDS_TAIL:-2}"

TS="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
RUN_DIR="$REPO_ROOT/results/runs/udp2raw/$TS"

SURICATA_LOG_DIR="$REPO_ROOT/results/suricata-alerts"
FAST_LOG="$SURICATA_LOG_DIR/fast.log"
EVE_LOG="$SURICATA_LOG_DIR/eve.json"

PCAP_FILE="$RUN_DIR/wg-udp2raw.pcap"

log() { echo "[*] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

mkdir -p "$RUN_DIR" "$SURICATA_LOG_DIR"

docker ps >/dev/null 2>&1 || die "Docker daemon not accessible."

# --- Start stack with udp2raw override ---
log "Starting stack with UDP2RAW obfuscation..."
COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_BASE -f $COMPOSE_OVERRIDE"
# Ensure clean slate
docker compose $COMPOSE_FLAGS down --remove-orphans >/dev/null 2>&1 || true
docker compose $COMPOSE_FLAGS up -d --build --remove-orphans

# --- Determine compose project name ---
PROJECT="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$TARGET_CONTAINER" 2>/dev/null || true)"
[[ -n "$PROJECT" ]] || die "Could not determine compose project from '$TARGET_CONTAINER'. Is the stack up?"

log "Compose project: $PROJECT"
log "Sniff network key: $SNIFF_KEY"

# --- Find docker network ID by compose labels ---
NET_ID="$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.network=$SNIFF_KEY" | head -n 1)"
[[ -n "$NET_ID" ]] || die "Could not find network for project=$PROJECT and network=$SNIFF_KEY."

# --- Resolve bridge interface name ---
BRIDGE_IF="$(docker network inspect "$NET_ID" -f '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)"

if [[ -z "${BRIDGE_IF:-}" || "$BRIDGE_IF" == "<no value>" ]]; then
  BRIDGE_IF="br-${NET_ID:0:12}"
fi

# Validate bridge interface
if ! ip link show "$BRIDGE_IF" >/dev/null 2>&1; then
  echo "[!] Bridge interface '$BRIDGE_IF' not found on host."
  echo "[!] Available bridges:"
  ip -br link | awk '$1 ~ /^br-|^docker0/ {print "    " $0}'
  die "Could not resolve a valid bridge interface for network id $NET_ID."
fi

# --- Resolve target IP ---
EXT_NET_ID="$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.network=external_net" | head -n 1)"
[[ -n "$EXT_NET_ID" ]] || die "Could not find external_net for project=$PROJECT."
EXT_NET_NAME="$(docker network inspect "$EXT_NET_ID" -f '{{.Name}}')"

TARGET_IP="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$EXT_NET_NAME\"}}{{.IPAddress}}{{end}}" "$TARGET_CONTAINER" 2>/dev/null || true)"
[[ -n "$TARGET_IP" ]] || die "Could not resolve target IP for '$TARGET_CONTAINER' on external_net."

log "Bridge IF: $BRIDGE_IF"
log "Target: $TARGET_CONTAINER => $TARGET_IP:$TARGET_PORT"
log "Run directory: $RUN_DIR"
log "UDP2RAW: WireGuard traffic wrapped in TCP/443"

# --- Reset logs ---
log "Resetting Suricata logs..."
sudo -v
sudo sh -lc " : > '$FAST_LOG' ; : > '$EVE_LOG' "

# --- Recreate Suricata ---
log "Recreating Suricata (BRIDGE_IF=$BRIDGE_IF)..."
BRIDGE_IF="$BRIDGE_IF" docker compose $COMPOSE_FLAGS up -d --force-recreate --no-deps suricata

# --- Wait for obfuscation proxies to be ready ---
log "Waiting for UDP2RAW tunnels to initialize..."
sleep 3

# --- Capture traffic ---
log "Starting tcpdump on $BRIDGE_IF (tcp/443 for udp2raw) -> $PCAP_FILE"
sudo tcpdump -ni "$BRIDGE_IF" tcp port 443 -w "$PCAP_FILE" >/dev/null 2>&1 &
TCPDUMP_PID=$!
sleep 1

# --- Generate traffic ---
log "Generating HTTP traffic through UDP2RAW tunnel ($HTTP_REQUESTS requests)..."
FAIL_COUNT=0
for i in $(seq 1 "$HTTP_REQUESTS"); do
  if ! timeout 10s docker exec "$CLIENT_CONTAINER" sh -lc "curl -s --max-time 5 http://$TARGET_IP:$TARGET_PORT/ >/dev/null"; then
      log "WARNING: Request $i failed or timed out."
      FAIL_COUNT=$((FAIL_COUNT+1))
      if [ "$FAIL_COUNT" -ge 10 ]; then
        die "Aborting: 10 consecutive failures detected."
      fi
  else
      printf "."
      FAIL_COUNT=0
  fi
done
echo ""

sleep "$TCPDUMP_SECONDS_TAIL"

# --- Stop tcpdump ---
log "Stopping tcpdump..."
sudo kill -2 "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

# --- Copy logs ---
log "Copying Suricata logs..."
sudo cp "$FAST_LOG" "$RUN_DIR/fast.log" 2>/dev/null || cp "$FAST_LOG" "$RUN_DIR/fast.log"
sudo cp "$EVE_LOG"  "$RUN_DIR/eve.json" 2>/dev/null || cp "$EVE_LOG"  "$RUN_DIR/eve.json"

log "Artifacts created:"
ls -lah "$RUN_DIR" | sed 's/^/    /'

log "Sanity checks (bytes):"
( sudo wc -c "$PCAP_FILE" "$RUN_DIR/eve.json" "$RUN_DIR/fast.log" 2>/dev/null || true ) | sed 's/^/    /'

log "Done."
