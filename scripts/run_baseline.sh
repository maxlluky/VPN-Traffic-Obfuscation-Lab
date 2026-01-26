#!/usr/bin/env bash
set -euo pipefail

TS=$(date -u +"%Y%m%dT%H%M%SZ")
NET="vpn-lab-baseline_client_net"
BR="br-$(docker network inspect "$NET" --format '{{.Id}}' | cut -c1-12)"

PCAP_DIR="$HOME/vpn-lab/results/runs/baseline/$TS"
mkdir -p "$PCAP_DIR"

echo "[*] Starting baseline stack..."
cd "$HOME/vpn-lab/compose"
docker compose -f baseline.yml up -d --build

echo "[*] Restarting Suricata on $BR..."
BRIDGE_IF="$BR" docker compose -f baseline.yml up -d --force-recreate suricata

PCAP="$PCAP_DIR/wg-baseline-$TS.pcap"
echo "[*] Capturing encrypted WG UDP traffic on $BR -> $PCAP"
sudo tcpdump -ni "$BR" udp port 51820 -w "$PCAP" >/dev/null 2>&1 &
TCPDUMP_PID=$!

# give tcpdump a moment to attach
sleep 1

echo "[*] Generating HTTP traffic through the tunnel..."
for i in $(seq 1 50); do
  docker exec -it client-node sh -lc "curl -s http://172.18.0.2 >/dev/null" || true
done

# capture a little tail (keepalives/response)
sleep 2

echo "[*] Stopping tcpdump..."
sudo kill -2 "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

echo "[*] Copying Suricata logs..."
cp "$HOME/vpn-lab/results/suricata-alerts/fast.log" "$PCAP_DIR/" 2>/dev/null || true
cp "$HOME/vpn-lab/results/suricata-alerts/eve.json" "$PCAP_DIR/" 2>/dev/null || true

echo "[*] Done. Artefacts in: $PCAP_DIR"
