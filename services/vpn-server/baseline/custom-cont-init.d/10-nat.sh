#!/usr/bin/with-contenv bash
set -e

echo "[init] Enabling IPv4 forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Interfaces inside vpn-gateway container vary by scenario (baseline vs obfs).
# We need to find the interface connected to external_net (172.30.30.0/24).
WAN_IF=$(ip -o addr show | grep '172.30.30.' | awk '{print $2}' | head -n 1)

if [ -z "$WAN_IF" ]; then
    echo "[init] WARNING: Could not detect WAN interface (172.30.30.x). Defaulting to eth0."
    WAN_IF="eth0"
else
    echo "[init] Detected WAN interface: $WAN_IF"
fi

echo "[init] Configuring iptables forwarding policy"
iptables -P FORWARD ACCEPT

# --- VPN (WireGuard) tunnel NAT ---
# Masquerade traffic from VPN clients (10.13.13.0/24) going out via WAN
iptables -t nat -C POSTROUTING -s 10.13.13.0/24 -o "$WAN_IF" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 10.13.13.0/24 -o "$WAN_IF" -j MASQUERADE

# Allow forwarding between wg0 and WAN
iptables -C FORWARD -i wg0 -o "$WAN_IF" -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i wg0 -o "$WAN_IF" -j ACCEPT

iptables -C FORWARD -i "$WAN_IF" -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i "$WAN_IF" -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "[init] NAT + forwarding configured for $WAN_IF"
