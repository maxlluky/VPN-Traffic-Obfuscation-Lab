#!/usr/bin/env bash
set -euo pipefail

# scripts/cleanup.sh
# Removes all Docker containers, networks, volumes, and images created by the lab.
# Usage: bash scripts/cleanup.sh [--all]
#   --all  Also remove built images (vpn-lab-*)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[*] $*"; }

REMOVE_IMAGES=false
if [[ "${1:-}" == "--all" ]]; then
    REMOVE_IMAGES=true
fi

# ── Stop and remove all compose stacks ────────────────────────────
COMPOSE_FILES=(
    "$REPO_ROOT/compose/compose.baseline.yml"
    "$REPO_ROOT/compose/compose.udp2raw.yml"
    "$REPO_ROOT/compose/compose.obfs4.yml"
)

for override in "${COMPOSE_FILES[@]}"; do
    name="$(basename "$override" .yml | sed 's/compose\.//')"
    log "Tearing down stack: $name ..."
    docker compose \
        --env-file "$REPO_ROOT/compose/.env" \
        -f "$REPO_ROOT/compose/compose.yml" \
        -f "$override" \
        down --remove-orphans --volumes 2>/dev/null || true
done

# ── Remove any leftover lab containers ────────────────────────────
CONTAINERS=$(docker ps -aq --filter "label=com.docker.compose.project=vpn-lab" 2>/dev/null || true)
if [[ -n "$CONTAINERS" ]]; then
    log "Removing leftover containers..."
    docker rm -f $CONTAINERS 2>/dev/null || true
fi

# ── Remove lab networks ───────────────────────────────────────────
NETWORKS=$(docker network ls -q --filter "label=com.docker.compose.project=vpn-lab" 2>/dev/null || true)
if [[ -n "$NETWORKS" ]]; then
    log "Removing lab networks..."
    docker network rm $NETWORKS 2>/dev/null || true
fi

# ── Remove built images (optional) ───────────────────────────────
if $REMOVE_IMAGES; then
    log "Removing lab images (vpn-lab-*)..."
    IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^vpn-lab-' || true)
    if [[ -n "$IMAGES" ]]; then
        docker rmi $IMAGES 2>/dev/null || true
    fi
fi

log "Cleanup complete."
docker ps -a --filter "label=com.docker.compose.project=vpn-lab" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true
