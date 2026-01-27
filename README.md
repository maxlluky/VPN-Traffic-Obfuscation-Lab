# VPN Obfuscation Lab (Bachelor Project)
This repository contains a reproducible Docker-based testbed to evaluate the detectability of
VPN traffic (baseline WireGuard) and VPN obfuscation techniques (e.g., obfs4, udp2raw) using Suricata IDS.

---
## Structure
- `compose.yml` – single Docker Compose file using profiles for baseline / obfs4 / udp2raw
- `services/` – container build contexts and service-specific configuration
  - `client/` – traffic generator (curl, iperf)
  - `wg-client/` – WireGuard client and routing logic
  - `gateway/` – WireGuard server / VPN gateway
  - `suricata/` – IDS configuration and rules
- `scripts/`
  - `runs/` – reproducible experiment runner scripts
  - `dev/` – helper scripts for local development
- `docs/` – architecture diagrams and notes
- `results/` – experiment outputs (sanitised, excluded from git)
- `pcaps/` – packet captures (excluded from git)

---
## Quickstart
This section describes how to run the baseline WireGuard VPN experiment and generate Suricata detection results.

**Prerequisites:**
1. Linux host (tested with Ubuntu / Arch Linux)
2. Docker Engine ≥ 24.x
3. Docker Compose v2
4. Kernel support for WireGuard (`wireguard`, `udp_tunnel`)
5. `bash`

**Verify Docker:**
```bash
docker --version
docker compose version
```

### 1️⃣ Clone the repository
```bash
git clone https://github.com/maxlluky/vpn-lab.git
cd vpn-lab-Cybersecurity
```

### 2️⃣ Prepare environment variables
Copy the example environment file:
```bash
cp .env.example .env
```
Edit .env if required (image versions, interface names, etc.).
> ⚠️ Do not commit .env — it may contain sensitive or system-specific configuration.

### 3️⃣ Start the baseline experiment stack
Build and start the containers:
```bash
docker compose up -d --build
```

Check container status:
```bash
docker compose ps -a
```
All services should reach the `running` state.

### 4️⃣ Run the baseline experiment
Execute the experiment runner script:
```bash
bash scripts/runs/run_baseline.sh
```

This script will:
- start packet capture
- generate VPN traffic
- collect Suricata alerts
- store experiment artefacts in results/

### 5️⃣ Inspect results

Suricata outputs are written to:
```bash
results/
├── suricata-alerts/
│   ├── eve.json
│   └── fast.log
└── runs/
    └── baseline/
        └── <timestamp>/      
```

**Example:**
```bash
jq '.alert.signature' results/suricata-alerts/eve.json
```

Ersetze Abschnitt 6 komplett durch:

### 6️⃣ Stop and clean up
Stop the experiment stack:
```bash
docker compose down
```

Remove volumes (optional):
```
docker compose down -v
```

---
## Experimental Notes
This lab uses a **single Docker Compose file with profiles** to enable or disable obfuscation
scenarios without duplicating configuration.

Available scenarios:
- **baseline** (default): plain WireGuard over UDP
- **udp2raw** (profile): WireGuard traffic wrapped using udp2raw
- **obfs4** (profile): WireGuard traffic transported via obfs4-based obfuscation components

Traffic generation is fully decoupled from the VPN implementation:
- `client-node` acts as a generic traffic generator (curl, iperf)
- `wg-client` implements the VPN client stack and routing logic

This separation ensures that **identical application traffic** is generated across all scenarios,
allowing meaningful comparison of detectability between baseline and obfuscated transports.

Suricata runs in **host mode** and passively monitors Docker bridge interfaces.
The correct capture interface is **resolved automatically at runtime** by the experiment runner
scripts and does not rely on hardcoded interface names.

Packet captures (`pcaps/`) and experiment results (`results/`) are intentionally excluded from Git.
Only sanitised excerpts should be included in documentation or publications.

---
## Architecture Overview
The experimental setup consists of two isolated Docker networks:

- `client_net (192.168.10.0/24)` – VPN client-side network
- `external_net (172.30.30.0/24)` – simulated external / target network

The VPN gateway is connected to both networks and routes traffic between them via a WireGuard tunnel.
Application traffic is generated exclusively by the `client-node` container, which shares its
network namespace with the `wg-client` container.

This design ensures a clean separation between:
- application-layer traffic generation, and
- transport-layer VPN and obfuscation mechanisms.

![etwork topology and traffic flow](/docs/Architecture-diagram.png)

---
## Next Steps
1. **Implement profile-based scenarios**
   - Add `profiles: ["udp2raw"]` services and integrate udp2raw between the WireGuard client and gateway.
   - Add `profiles: ["obfs4"]` services and route WireGuard traffic through obfs4-based transport components.

2. **Single entrypoint runner**
   - Add a unified runner script such as:
     - `bash scripts/runs/run_scenario.sh baseline|obfs4|udp2raw`
   - The script should start the correct profile, wait for readiness, generate traffic, and collect artefacts.

3. **Health checks and startup order**
   - Add `healthcheck` to critical services (gateway, suricata, target) and use `depends_on` with health conditions where supported.

4. **Result comparison**
   - Add a small script to compare Suricata outputs across scenarios (baseline vs obfs4 vs udp2raw), e.g. signature counts, alert rate, timing.

5. **Documentation**
   - Add a short architecture diagram and explain where obfuscation is applied in the traffic path for each profile.