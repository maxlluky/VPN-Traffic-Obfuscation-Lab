#!/usr/bin/env bash
set -euo pipefail

NET="vpn-lab-baseline_client_net"
BR="br-$(docker network inspect "$NET" --format '{{.Id}}' | cut -c1-12)"

echo "[*] Using bridge: $BR"

cd "$HOME/vpn-lab/compose"

# recreate suricata with updated interface via env var substitution
BRIDGE_IF="$BR" docker compose -f baseline.yml up -d --force-recreate suricata
