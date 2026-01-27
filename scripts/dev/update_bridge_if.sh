#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/compose.yml}"

# Which compose network key should Suricata sniff on?
SNIFF_KEY="${SNIFF_KEY:-external_net}"  # external_net|client_net

TARGET_CONTAINER="${TARGET_CONTAINER:-target-server}"

log() { echo "[*] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || die "Env file not found: $ENV_FILE"

docker ps >/dev/null 2>&1 || die "Docker daemon not accessible."

# Ensure stack is up so labels/networks exist
log "Ensuring stack is up (to resolve compose project/network)..."
docker compose -f "$COMPOSE_FILE" up -d >/dev/null

PROJECT="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$TARGET_CONTAINER" 2>/dev/null || true)"
[[ -n "$PROJECT" ]] || die "Could not determine compose project from '$TARGET_CONTAINER'. Is it running?"

NET_ID="$(docker network ls -q \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --filter "label=com.docker.compose.network=$SNIFF_KEY" | head -n 1)"
[[ -n "$NET_ID" ]] || die "Could not find network id for project=$PROJECT network=$SNIFF_KEY"

# Try best source first, then fallback
BRIDGE_IF="$(docker network inspect "$NET_ID" -f '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)"
if [[ -z "${BRIDGE_IF:-}" || "$BRIDGE_IF" == "<no value>" ]]; then
  BRIDGE_IF="br-${NET_ID:0:12}"
fi

# Validate interface exists
if ! ip link show "$BRIDGE_IF" >/dev/null 2>&1; then
  log "Available bridges:"
  ip -br link | awk '$1 ~ /^br-|^docker0/ {print "    " $0}'
  die "Resolved BRIDGE_IF=$BRIDGE_IF but interface not found on host."
fi

log "Resolved BRIDGE_IF=$BRIDGE_IF (project=$PROJECT, network=$SNIFF_KEY)"

# Update or append BRIDGE_IF in .env (no sed -i portability issues)
tmp="$(mktemp)"
if grep -qE '^BRIDGE_IF=' "$ENV_FILE"; then
  awk -v v="$BRIDGE_IF" 'BEGIN{done=0} { if ($0 ~ /^BRIDGE_IF=/){print "BRIDGE_IF="v; done=1} else print $0 } END{ if(!done) print "BRIDGE_IF="v }' "$ENV_FILE" > "$tmp"
else
  cat "$ENV_FILE" > "$tmp"
  printf "\nBRIDGE_IF=%s\n" "$BRIDGE_IF" >> "$tmp"
fi

mv "$tmp" "$ENV_FILE"
log "Updated $ENV_FILE"
