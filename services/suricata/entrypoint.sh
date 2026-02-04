#!/bin/bash
set -e

echo "[*] Starting Suricata Entrypoint..."

# Update Rules
if command -v suricata-update &> /dev/null; then
    echo "[*] Running suricata-update (ET Open)..."
    suricata-update --no-reload
else
    echo "[!] suricata-update not found, skipping rule update."
fi

# Count Loaded Rules
# suricata-update writes to /var/lib/suricata/rules/suricata.rules by default
RULES_FILE="/var/lib/suricata/rules/suricata.rules"
RULE_COUNT=0
if [ -f "$RULES_FILE" ]; then
    RULE_COUNT=$(grep -c '^alert' "$RULES_FILE" || true)
    echo "[*] Loaded Rules Count: $RULE_COUNT"
else
    echo "[!] Rules file not found at $RULES_FILE"
fi

# Write metadata for extraction later
# We write to a volume shared with host (e.g., /var/log/suricata)
echo "{\"suricata_version\": \"$(suricata -V | head -n1)\", \"loaded_rules_count\": $RULE_COUNT, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > /var/log/suricata/suricata_meta.json

# Start Suricata
echo "[*] Executing Suricata..."
exec suricata "$@"
