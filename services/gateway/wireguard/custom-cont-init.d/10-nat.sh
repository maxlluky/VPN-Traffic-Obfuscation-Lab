#!/usr/bin/with-contenv bash
set -e

echo "[init] Enabling IPv4 forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Interfaces inside vpn-gateway container:
# eth0 = client_net (172.19.0.0/16)
# eth1 = external_net (172.18.0.0/16)
# wg0  = WireGuard tunnel interface (10.13.13.0/24)

echo "[init] Configuring iptables forwarding policy"
iptables -P FORWARD ACCEPT

# --- Baseline (plain) routing NAT (optional) ---
# If you still want plain client_net -> external_net connectivity:
iptables -t nat -C POSTROUTING -s 172.19.0.0/16 -o eth1 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 172.19.0.0/16 -o eth1 -j MASQUERADE

# --- VPN (WireGuard) tunnel NAT ---
# Required so target replies can return via gateway without static routes.
iptables -t nat -C POSTROUTING -s 10.13.13.0/24 -o eth1 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 10.13.13.0/24 -o eth1 -j MASQUERADE

# Allow forwarding between wg0 and eth1
iptables -C FORWARD -i wg0 -o eth1 -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i wg0 -o eth1 -j ACCEPT

iptables -C FORWARD -i eth1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i eth1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "[init] NAT + forwarding configured"
