#!/bin/bash
# scripts/pcap_to_packet_csv.sh
# Usage: ./pcap_to_packet_csv.sh <input.pcap> <output.csv>

INPUT_PCAP="$1"
OUTPUT_CSV="$2"

if [[ -z "$INPUT_PCAP" || -z "$OUTPUT_CSV" ]]; then
    echo "Usage: $0 <input.pcap> <output.csv>"
    exit 1
fi

echo "[*] Extracting packet features from $INPUT_PCAP to $OUTPUT_CSV..."

# Check tshark presence
if ! command -v tshark &> /dev/null; then
    echo "[!] tshark not found. Install wireshark-cli/tshark."
    exit 1
fi

# Tshark Command
# Fields:
# frame.time_epoch: Timestamp
# frame.len: Wire length
# ip.src, ip.dst: IP addresses
# ip.proto: Protocol (6=TCP, 17=UDP)
# tcp.srcport, tcp.dstport: TCP ports
# udp.srcport, udp.dstport: UDP ports
# tls.handshake.type: 1 = Client Hello (indicates TLS start)

tshark -r "$INPUT_PCAP" \
    -T fields \
    -E separator=, \
    -E header=y \
    -E quote=d \
    -e frame.time_epoch \
    -e frame.len \
    -e ip.src \
    -e ip.dst \
    -e ip.proto \
    -e tcp.srcport \
    -e tcp.dstport \
    -e udp.srcport \
    -e udp.dstport \
    -e tls.handshake.type \
    > "$OUTPUT_CSV"

echo "[*] Extraction complete: $(wc -l < "$OUTPUT_CSV") lines."
