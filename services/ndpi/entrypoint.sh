#!/bin/sh
set -e

LOG_DIR="/var/log/ndpi"
mkdir -p "$LOG_DIR"

# Write metadata (version + timestamp) for artifact collection
NDPI_VER=$(ndpiReader --version 2>&1 | head -1 | sed 's/Welcome to //')
echo "{\"ndpi_version\": \"${NDPI_VER}\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    > "$LOG_DIR/ndpi_meta.json"

echo "[*] nDPI DPI: $NDPI_VER"
echo "[*] Starting ndpiReader on interface: $@"

# ndpiReader ignores SIGTERM but responds to SIGINT.
# Docker sends SIGTERM on 'docker stop', so we trap it and forward as SIGINT.
ndpiReader "$@" \
    -C "$LOG_DIR/flows.csv" \
    > "$LOG_DIR/summary.txt" 2>&1 &
NDPI_PID=$!

trap "kill -INT $NDPI_PID 2>/dev/null; wait $NDPI_PID 2>/dev/null; exit 0" TERM INT
wait $NDPI_PID
