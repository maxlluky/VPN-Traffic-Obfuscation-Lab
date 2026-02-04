#!/bin/sh
set -eux

echo "[*] Checking for /config/wg0.conf..."
ls -l /config/wg0.conf

# Bring up WireGuard using wg-quick (handles routes based on AllowedIPs)
wg-quick up /config/wg0.conf

echo "[*] WireGuard started, sleeping..."
exec sleep infinity