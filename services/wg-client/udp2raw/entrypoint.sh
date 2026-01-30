#!/bin/sh
set -e

# Default values
PASSWORD="${PASSWORD:-vpn-lab-secret}"
RAW_MODE="${RAW_MODE:-faketcp}"
CIPHER_MODE="${CIPHER_MODE:-aes128cbc}"
AUTH_MODE="${AUTH_MODE:-md5}"

if [ "$MODE" = "client" ]; then
    echo "[*] Starting UDP2RAW Client..."
    
    # Resolve hostname to IP
    SERVER_IP=$(getent hosts "$SERVER" | awk '{ print $1 }' | head -n 1)
    if [ -z "$SERVER_IP" ]; then
        echo "[!] Could not resolve SERVER: $SERVER"
        exit 1
    fi
    echo "    Server: ${SERVER} (${SERVER_IP}):${SERVER_PORT}"
    echo "    Local Listen: 127.0.0.1:${TARGET_PORT}" # TARGET_PORT is used as local listen port here (51820)
    
    exec udp2raw -c \
        -l "127.0.0.1:${TARGET_PORT}" \
        -r "${SERVER_IP}:${SERVER_PORT}" \
        -k "$PASSWORD" \
        --raw-mode "$RAW_MODE" \
        --cipher-mode "$CIPHER_MODE" \
        --auth-mode "$AUTH_MODE" \
        -a
else
    echo "[!] Invalid MODE: $MODE"
    exit 1
fi
