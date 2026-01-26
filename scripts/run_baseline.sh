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

echo "[*] Capturing encrypted WG UDP traffic..."
sudo timeout 20 tcpdump -ni "$BR" udp port 51820 -w "$PCAP_DIR/wg-baseline-$TS.pcap" >/dev/null 2>&1 || true

echo "[*] Generating HTTP traffic through the tunnel..."
for i in $(seq 1 50); do
  docker exec -it client-node sh -lc "curl -s http://172.18.0.2 >/dev/null" || true
done

echo "[*] Copying Suricata logs..."
cp "$HOME/vpn-lab/results/suricata-alerts/fast.log" "$PCAP_DIR/" 2>/dev/null || true
cp "$HOME/vpn-lab/results/suricata-alerts/eve.json" "$PCAP_DIR/" 2>/dev/null || true

echo "[*] Done. Artefacts in: $PCAP_DIR"
