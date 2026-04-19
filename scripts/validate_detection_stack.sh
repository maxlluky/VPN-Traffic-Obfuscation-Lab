#!/usr/bin/env bash
set -euo pipefail

# scripts/validate_ids.sh
# Positive control: proves Suricata, Zeek & nDPI are functional by sending
# plain (unencrypted) HTTP traffic across the monitored bridge interface.
#
# Expected outcome:
#   - Suricata: ET Open HTTP alerts (e.g. ET POLICY, ET INFO)
#   - Zeek:     conn.log entries with service="http"
#   - nDPI:     Detected protocols (e.g. HTTP)
#
# This validates that the absence of alerts in VPN scenarios is a genuine
# finding, not a tool misconfiguration.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_common_vars
check_docker

COMPOSE_OVERRIDE="$REPO_ROOT/compose/compose.validate.yml"
COMPOSE_FLAGS="--env-file $REPO_ROOT/compose/.env -f $REPO_ROOT/compose/compose.yml -f $COMPOSE_OVERRIDE"

TS="$(date -u +"%d-%m-%Y-%H-%M-%S")"
RUN_DIR="$REPO_ROOT/results/runs/validation/$TS"
PCAP_FILE="$RUN_DIR/validation.pcap"
mkdir -p "$RUN_DIR"

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  IDS VALIDATION — Positive Control (Plain HTTP)"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Start stack ──────────────────────────────────────────────
export SCENARIO="validation"
start_stack "$COMPOSE_FLAGS"

# Detect bridge interface
TARGET_CONTAINER="target-server"
SNIFF_KEY="client_net"
detect_network_info "$TARGET_CONTAINER" "$SNIFF_KEY"

# Reset IDS logs (includes wait_for_suricata — waits until engine is ready)
reset_ids_logs "$BRIDGE_IF" "$COMPOSE_FLAGS"

# ── Start capture ────────────────────────────────────────────
# Capture ALL traffic (no filter) to see everything
start_tcpdump "$BRIDGE_IF" "" "$PCAP_FILE"

# ── Generate plain HTTP traffic ──────────────────────────────
log "Sending plain HTTP requests from http-client → target-server..."

# Traffic patterns designed to trigger ET Open signatures
docker exec http-client sh -c "
  # Basic HTTP GET requests (generates flow data)
  for i in \$(seq 1 10); do
    curl -s -o /dev/null -w 'Request %{http_code} ' http://172.30.30.10/ 2>/dev/null || true
  done
  echo ''

  # ET POLICY: curl user-agent (SID 2013028)
  curl -s -o /dev/null -A 'curl/7.88.0' http://172.30.30.10/ 2>/dev/null || true

  # ET POLICY: wget user-agent (SID 2013029)
  curl -s -o /dev/null -A 'Wget/1.21' http://172.30.30.10/ 2>/dev/null || true

  # ET POLICY: Python-urllib (SID 2013030, 2014726)
  curl -s -o /dev/null -A 'Python-urllib/3.11' http://172.30.30.10/ 2>/dev/null || true

  # ET INFO: EXE download attempt (triggers on .exe extension in URI)
  curl -s -o /dev/null http://172.30.30.10/test.exe 2>/dev/null || true

  # ET POLICY: PE EXE or DLL Windows file download HTTP (content match on MZ header)
  # We request binary content to generate varied flows
  curl -s -o /dev/null http://172.30.30.10/assets/dummy_50k.bin 2>/dev/null || true
  curl -s -o /dev/null http://172.30.30.10/assets/dummy_200k.bin 2>/dev/null || true

  # ET INFO: Possible .bat file download (SID 2019137)
  curl -s -o /dev/null http://172.30.30.10/test.bat 2>/dev/null || true

  # ET INFO: Possible .ps1 file download (SID 2019715)
  curl -s -o /dev/null http://172.30.30.10/test.ps1 2>/dev/null || true

  # DNS lookup (if possible)
  nslookup example.com 2>/dev/null || true
" || log "WARNING: Some requests may have failed (expected in isolated network)."

log "HTTP traffic generation complete."
sleep 3

# ── Stop capture ─────────────────────────────────────────────
stop_tcpdump "$TCPDUMP_PID"

# ── Collect & Analyse ────────────────────────────────────────
log "Collecting artifacts..."

# Stop Suricata, Zeek & nDPI to flush all logs to disk
docker stop suricata-ids >/dev/null 2>&1 || true
docker stop zeek-nsm >/dev/null 2>&1 || true
docker stop ndpi-dpi >/dev/null 2>&1 || true
sleep 3

mkdir -p "$RUN_DIR/pcap" "$RUN_DIR/suricata" "$RUN_DIR/zeek" "$RUN_DIR/ndpi"

[ -f "$PCAP_FILE" ] && mv "$PCAP_FILE" "$RUN_DIR/pcap/"
sudo cp "$FAST_LOG" "$RUN_DIR/suricata/fast.log" 2>/dev/null || true
sudo cp "$EVE_LOG"  "$RUN_DIR/suricata/eve.json" 2>/dev/null || true
sudo cp "$ZEEK_LOG_DIR"/*.log "$RUN_DIR/zeek/" 2>/dev/null || true
sudo cp "$NDPI_LOG_DIR"/flows.csv  "$RUN_DIR/ndpi/" 2>/dev/null || true
sudo cp "$NDPI_LOG_DIR"/summary.txt "$RUN_DIR/ndpi/" 2>/dev/null || true

# ── Results ──────────────────────────────────────────────────
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  VALIDATION RESULTS"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Suricata alerts
log ""
log "Suricata Alerts:"
if [ -f "$RUN_DIR/suricata/eve.json" ]; then
    python3 -c "
import json, sys
alerts=[]
with open('$RUN_DIR/suricata/eve.json') as f:
    for line in f:
        try:
            e=json.loads(line)
            if e.get('event_type')=='alert':
                alerts.append(e['alert']['signature'])
        except: pass
seen=set()
for a in alerts:
    if a not in seen:
        print(f'    ✓ {a}')
        seen.add(a)
print(f'  Total: {len(alerts)} alerts ({len(seen)} unique signatures)')
sys.exit(0 if alerts else 1)
" 2>/dev/null || log "  ✗ No alerts — Suricata may not be detecting HTTP traffic"
fi

# Suricata packet stats
python3 -c "
import json
with open('$RUN_DIR/suricata/eve.json') as f:
    for line in f:
        try:
            e=json.loads(line)
            if e.get('event_type')=='stats':
                cap=e['stats']['capture']
                dec=e['stats']['decoder']
                print(f'  Packets captured: {cap.get(\"kernel_packets\",\"N/A\")}')
                print(f'  Packets decoded:  {dec.get(\"pkts\",\"N/A\")}')
                print(f'  IPv4:             {dec.get(\"ipv4\",\"N/A\")}')
                print(f'  TCP:              {dec.get(\"tcp\",\"N/A\")}')
                break
        except: pass
" 2>/dev/null || true

# Zeek services
log ""
log "Zeek Service Detection:"
if [ -f "$RUN_DIR/zeek/conn.log" ]; then
    python3 -c "
import json
flows=[]
with open('$RUN_DIR/zeek/conn.log') as f:
    for line in f:
        try:
            e=json.loads(line)
            svc=e.get('service','-')
            proto=e.get('proto','?')
            dst=e.get('id.resp_p','?')
            flows.append(f'    ✓ {proto}/{dst} → service={svc}')
        except: pass
for fl in flows[:15]:
    print(fl)
print(f'  Total: {len(flows)} flows')
" 2>/dev/null || echo "  (parse error)"
else
    log "  ✗ No conn.log found"
fi

# nDPI protocols
log ""
log "nDPI Protocol Detection:"
if [ -f "$RUN_DIR/ndpi/summary.txt" ]; then
    python3 -c "
import sys
with open('$RUN_DIR/ndpi/summary.txt') as f:
    lines = f.readlines()
in_protos = False
for line in lines:
    if 'Detected protocols:' in line:
        in_protos = True
        continue
    if in_protos and line.strip():
        parts = line.strip().split()
        if parts:
            print(f'    > {line.strip()}')
    elif in_protos and not line.strip():
        break
" 2>/dev/null || log "  (parse error)"
else
    log "  - No nDPI summary found"
fi

# PCAP packet count
log ""
PCAP_PATH="$RUN_DIR/pcap/validation.pcap"
if [ -f "$PCAP_PATH" ]; then
    PKT_COUNT=$(tshark -r "$PCAP_PATH" -T fields -e frame.number 2>/dev/null | wc -l)
    log "PCAP: $PKT_COUNT packets captured"
fi

log ""
log "Artifacts saved to: $RUN_DIR"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Teardown ─────────────────────────────────────────────────
log "Tearing down validation stack..."
docker compose $COMPOSE_FLAGS down --remove-orphans >/dev/null 2>&1 || true

log "Done."
