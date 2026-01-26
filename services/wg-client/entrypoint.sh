#!/bin/sh
set -eu

# Ensure the config exists
test -f /config/wg0.conf

# Bring up WireGuard (wg-quick preferred, fallback to manual)
if command -v wg-quick >/dev/null 2>&1; then
  wg-quick up /config/wg0.conf
else
  # Minimal manual setup (expects InterfaceAddress in config)
  ip link add wg0 type wireguard
  wg setconf wg0 /config/wg0.conf
  ip address add 10.13.13.2/32 dev wg0
  ip link set up dev wg0
  # Route only the target network over wg0
  ip route add 172.18.0.0/16 dev wg0 || true
fi

ip route add 172.18.0.0/16 dev wg0 2>/dev/null || true

exec sleep infinity