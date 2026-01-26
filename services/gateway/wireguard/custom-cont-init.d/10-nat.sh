#!/usr/bin/with-contenv bash
set -e

# Enable forwarding (should already be set via sysctl, but keep it explicit)
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Allow forwarding
iptables -P FORWARD ACCEPT

# NAT: masquerade client_net traffic out towards external_net
# client_net subnet: 172.19.0.0/16
# external side interface inside gateway: eth1
iptables -t nat -C POSTROUTING -s 172.19.0.0/16 -o eth1 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 172.19.0.0/16 -o eth1 -j MASQUERADE

echo "[init] NAT + forwarding configured"
