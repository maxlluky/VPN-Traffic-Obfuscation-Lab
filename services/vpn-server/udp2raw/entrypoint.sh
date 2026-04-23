#!/bin/sh
set -e

# udp2raw gateway entrypoint
# Tunnels UDP/51820 (WireGuard) through TCP/443

MODE="${MODE:-server}"
LISTEN_PORT="${LISTEN_PORT:-443}"
TARGET_HOST="${TARGET_HOST:-gateway}"
TARGET_PORT="${TARGET_PORT:-51820}"

echo "[*] udp2raw gateway ($MODE mode)"
echo "[*] Listening on port $LISTEN_PORT"
echo "[*] Forwarding to $TARGET_HOST:$TARGET_PORT"

# udp2raw usage: udp2raw [-s server_mode] [-c client_mode] [-l listen_port] [-r remote_addr:remote_port] [-k password] [--raw-mode] [...]
# For TCP wrapping: --raw-mode TCP

if [ "$MODE" = "server" ]; then
  exec udp2raw \
    -s \
    -l "0.0.0.0:$LISTEN_PORT" \
    -r "$TARGET_HOST:$TARGET_PORT" \
    --raw-mode faketcp \
    -k "vpn-lab-obfs" \
    -a \
    > /dev/stdout 2>&1
else
  exec udp2raw \
    -c \
    -l "127.0.0.1:$TARGET_PORT" \
    -r "$TARGET_IP:$LISTEN_PORT" \
    --raw-mode TCP \
    -k "vpn-lab-obfs"
fi
