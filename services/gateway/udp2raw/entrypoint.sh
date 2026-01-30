#!/bin/sh
set -e

# Default values
PASSWORD="${PASSWORD:-vpn-lab-secret}"
RAW_MODE="${RAW_MODE:-faketcp}"
CIPHER_MODE="${CIPHER_MODE:-aes128cbc}"
AUTH_MODE="${AUTH_MODE:-md5}"

if [ "$MODE" = "server" ]; then
    echo "[*] Starting UDP2RAW Server..."
    echo "    Listen: 0.0.0.0:${LISTEN_PORT}"
    
    # Resolve hostname to IP
    TARGET_IP=$(getent hosts "$TARGET_HOST" | awk '{ print $1 }' | head -n 1)
    if [ -z "$TARGET_IP" ]; then
        echo "[!] Could not resolve TARGET_HOST: $TARGET_HOST"
        exit 1
    fi
    echo "    Target: ${TARGET_HOST} (${TARGET_IP}):${TARGET_PORT}"

    exec udp2raw -s \
        -l "0.0.0.0:${LISTEN_PORT}" \
        -r "${TARGET_IP}:${TARGET_PORT}" \
        -k "$PASSWORD" \
        --raw-mode "$RAW_MODE" \
        --cipher-mode "$CIPHER_MODE" \
        --auth-mode "$AUTH_MODE" \
        -a
else
    echo "[!] Invalid MODE: $MODE"
    exit 1
fi
