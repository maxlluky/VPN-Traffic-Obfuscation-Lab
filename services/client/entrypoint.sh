#!/bin/sh
set -eu

# Wait briefly for network to be up
sleep 1

# Route traffic to external_net via the gateway (connected to both networks)
# client_net gateway IP (vpn-gateway on eth0): 172.19.0.2
# external_net subnet: 172.18.0.0/16
#       ip route add 172.18.0.0/16 via 172.19.0.2 2>/dev/null || true

# Keep container running
exec sleep infinity