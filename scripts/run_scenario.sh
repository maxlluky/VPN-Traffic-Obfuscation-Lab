#!/usr/bin/env bash
set -euo pipefail

# scripts/run_scenario.sh
# Unified runner for all VPN obfuscation scenarios.
# Usage: bash scripts/run_scenario.sh <scenario> [mode]
# Scenarios: baseline, udp2raw, obfs4
# Modes:     burst (default), streaming

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ── Input validation ─────────────────────────────────────────────
SCENARIO="${1:-}"
TRAFFIC_MODE="${2:-${TRAFFIC_MODE:-burst}}"
export TRAFFIC_MODE

if [[ -z "$SCENARIO" ]]; then
    die "Usage: $0 <scenario> [mode]  (scenario: baseline | udp2raw | obfs4, mode: burst | streaming)"
fi

if [[ "$TRAFFIC_MODE" != "burst" && "$TRAFFIC_MODE" != "streaming" ]]; then
    die "Unknown traffic mode: '$TRAFFIC_MODE'. Use: burst | streaming"
fi

setup_common_vars

# ── Scenario-specific configuration ──────────────────────────────
case "$SCENARIO" in
    baseline)
        SNIFF_KEY="${SNIFF_KEY:-client_net}"
        PCAP_NAME="wg-baseline.pcap"
        TCPDUMP_FILTER="udp port 51820"
        COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.baseline.yml}"
        TUNNEL_WAIT=0
        SCENARIO_LABEL="Baseline: Plain WireGuard (no obfuscation)"
        ;;
    udp2raw)
        SNIFF_KEY="${SNIFF_KEY:-client_net}"
        PCAP_NAME="wg-udp2raw.pcap"
        TCPDUMP_FILTER="tcp port 443"
        COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.udp2raw.yml}"
        TUNNEL_WAIT=3
        SCENARIO_LABEL="UDP2RAW: WireGuard traffic wrapped in TCP/443"
        ;;
    obfs4)
        SNIFF_KEY="${SNIFF_KEY:-client_net}"
        OBFS4_PORT="${OBFS4_PORT:-12345}"
        PCAP_NAME="wg-obfs4.pcap"
        TCPDUMP_FILTER="port ${OBFS4_PORT}"
        COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-$REPO_ROOT/compose/compose.obfs4.yml}"
        TUNNEL_WAIT=3
        SCENARIO_LABEL="OBFS4: WireGuard traffic wrapped in obfs4 protocol"
        ;;
    *)
        die "Unknown scenario: '$SCENARIO'. Use: baseline | udp2raw | obfs4"
        ;;
esac

# ── Common setup ─────────────────────────────────────────────────
TS="$(date -u +"%d-%m-%Y-%H-%M-%S")"
RUN_DIR="$REPO_ROOT/results/runs/$SCENARIO/$TS"
PCAP_FILE="$RUN_DIR/$PCAP_NAME"

mkdir -p "$RUN_DIR"
check_docker

COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $COMPOSE_BASE -f $COMPOSE_OVERRIDE"

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Scenario:       $SCENARIO_LABEL"
log "  Traffic mode:   $TRAFFIC_MODE"
log "  Run directory:  $RUN_DIR"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

# ── Execution ────────────────────────────────────────────────────
export SCENARIO

start_stack "$COMPOSE_FLAGS"
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

reset_ids_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

if [[ "$TUNNEL_WAIT" -gt 0 ]]; then
    log "Waiting ${TUNNEL_WAIT}s for tunnel initialization..."
    sleep "$TUNNEL_WAIT"
fi

start_tcpdump "$BRIDGE_IF" "$TCPDUMP_FILTER" "$PCAP_FILE"

generate_traffic "$CLIENT_CONTAINER" "$TARGET_IP" "$TARGET_PORT" "$HTTP_REQUESTS" "$RUN_DIR"

sleep "$TCPDUMP_SECONDS_TAIL"
stop_tcpdump "$TCPDUMP_PID"

collect_artifacts "$RUN_DIR" "$PCAP_FILE"

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Run complete: $SCENARIO ($TRAFFIC_MODE)"
log "  Artifacts:    $RUN_DIR"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
