#!/bin/sh
set -eu

test -f /config/wg0.conf

# Bring up WireGuard using wg-quick (handles routes based on AllowedIPs)
wg-quick up /config/wg0.conf

exec sleep infinity