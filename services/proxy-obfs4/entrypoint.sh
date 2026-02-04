#!/bin/bash
set -e

# Configuration
MODE="${MODE:-client}"
SERVER="${SERVER:-obfs4-gateway}"
SERVER_PORT="${SERVER_PORT:-12345}"
LISTEN_PORT="${LISTEN_PORT:-12345}"
TARGET_HOST="${TARGET_HOST:-gateway}"
TARGET_PORT="${TARGET_PORT:-51820}"
PASSWORD="${PASSWORD:-lab-obfuscation-secret}"

echo "========================================================"
echo "Starting obfs4 service in $MODE mode"
echo "========================================================"

# Make adapter executable (already done in Dockerfile)
# chmod +x /usr/local/bin/pt_adapter.py

if [ "$MODE" = "server" ]; then
  echo "[*] Server Configuration:"
  echo "    Listen Port: $LISTEN_PORT"
  echo "    State Dir:   /var/lib/obfs4"
  
  export TOR_PT_STATE_LOCATION=/var/lib/obfs4
  
  exec ssserver \
    -s "0.0.0.0:$LISTEN_PORT" \
    -k "$PASSWORD" \
    -m "chacha20-ietf-poly1305" \
    --plugin "/usr/local/bin/pt_adapter.py" \
    --plugin-opts "server" \
    -U \
    -v

else
  # CLIENT MODE
  echo "[*] Client Configuration:"
  echo "    Server:      $SERVER:$SERVER_PORT"
  echo "    Local Bind:  0.0.0.0:$TARGET_PORT"
  
  # Read Cert
  if [ -f "/public_cert.txt" ]; then
    CERT=$(cat /public_cert.txt)
  else
    echo "[!] /public_cert.txt not found!"
    exit 1
  fi
  echo "    Cert: ${CERT:0:20}..."

  exec sslocal \
    --protocol tunnel \
    -s "$SERVER:$SERVER_PORT" \
    -b "0.0.0.0:$TARGET_PORT" \
    --forward-addr "$TARGET_HOST:$TARGET_PORT" \
    -k "$PASSWORD" \
    -m "chacha20-ietf-poly1305" \
    --plugin "/usr/local/bin/pt_adapter.py" \
    --plugin-opts "cert=$CERT;iat-mode=0" \
    -U \
    -v
fi
