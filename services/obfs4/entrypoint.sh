#!/bin/sh
set -e

# obfs4 proxy entrypoint
# Routes either as server (gateway side) or client (wg-client side)

MODE="${MODE:-client}"
SERVER="${SERVER:-obfs4-gateway}"
SERVER_PORT="${SERVER_PORT:-12345}"
LISTEN_PORT="${LISTEN_PORT:-12345}"
TARGET_HOST="${TARGET_HOST:-gateway}"
TARGET_PORT="${TARGET_PORT:-51820}"

echo "[*] obfs4proxy ($MODE mode)"

# Create PT_STATE directory for obfs4 state files
mkdir -p /tmp/obfs4-state

if [ "$MODE" = "server" ]; then
  echo "[*] Server: Listening on port $LISTEN_PORT"
  echo "[*] Server: Forwarding to $TARGET_HOST:$TARGET_PORT"
  
  # obfs4 server configuration
  cat > /tmp/obfs4-server.conf <<EOF
{
  "state": "/tmp/obfs4-state",
  "logLevel": "info",
  "transports": ["obfs4"],
  "ptListenAddr": "0.0.0.0:$LISTEN_PORT",
  "orPort": "$TARGET_HOST:$TARGET_PORT"
}
EOF
  
  exec obfs4proxy \
    -logLevel info \
    -transports obfs4 \
    -bindAddr 0.0.0.0:$LISTEN_PORT
    
else
  echo "[*] Client: Connecting to $SERVER:$SERVER_PORT"
  echo "[*] Client: Listening on 127.0.0.1:$TARGET_PORT"
  
  # obfs4 client configuration
  cat > /tmp/obfs4-client.conf <<EOF
{
  "state": "/tmp/obfs4-state",
  "logLevel": "info",
  "transports": ["obfs4"],
  "ptListenAddr": "127.0.0.1:$TARGET_PORT",
  "orAddr": "$SERVER:$SERVER_PORT"
}
EOF
  
  exec obfs4proxy \
    -logLevel info \
    -transports obfs4 \
    -bindAddr 127.0.0.1:$TARGET_PORT \
    -serverAddr "$SERVER:$SERVER_PORT"
fi
