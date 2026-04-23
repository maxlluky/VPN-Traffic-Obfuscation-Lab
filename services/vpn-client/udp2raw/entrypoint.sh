#!/bin/sh
set -e

# udp2raw client entrypoint
# Receives TCP/443 traffic and unwraps it as UDP/51820

MODE="${MODE:-client}"
SERVER="${SERVER:-udp2raw-gateway}"
SERVER_PORT="${SERVER_PORT:-443}"
TARGET_PORT="${TARGET_PORT:-51820}"

echo "[*] udp2raw client ($MODE mode)"
echo "[*] Connecting to $SERVER:$SERVER_PORT"
echo "[*] Forwarding to localhost:$TARGET_PORT"

# udp2raw client mode listens locally and sends to remote server
exec udp2raw \
  -c \
  -l "127.0.0.1:$TARGET_PORT" \
  -r "$SERVER:$SERVER_PORT" \
  --raw-mode faketcp \
  -k "vpn-lab-obfs" \
  -a \
  > /dev/stdout 2>&1
