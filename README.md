# VPN Obfuscation Lab (Bachelor Project)

This repository contains a reproducible Docker-based testbed to evaluate the detectability of
VPN traffic (baseline WireGuard) and VPN obfuscation techniques (e.g., obfs4, udp2raw) using Suricata IDS.

## Structure
- `compose/` – docker compose scenarios (baseline / obfs4 / udp2raw)
- `services/` – container build contexts and configs (client, gateway, suricata, target)
- `docs/` – notes, diagrams, screenshots (no sensitive data)
- `results/` – exported logs/metrics (sanitised)
- `pcaps/` – packet captures (excluded from git)

## Quick start (baseline)
TBD
