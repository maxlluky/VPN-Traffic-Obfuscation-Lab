# VPN Obfuscation Lab (Bachelor Project)

This repository contains a reproducible Docker-based testbed to evaluate the detectability of
VPN traffic (baseline WireGuard) and VPN obfuscation techniques (e.g., obfs4, udp2raw) using Suricata IDS.

## Structure
- `compose/` – docker compose scenarios (baseline / obfs4 / udp2raw)
- `services/` – container build contexts and configs (client, gateway, suricata, target)
- `docs/` – notes, diagrams, screenshots (no sensitive data)
- `results/` – exported logs/metrics (sanitised)
- `pcaps/` – packet captures (excluded from git)
- `scripts/` – 

## 🚀 Quickstart
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
docker compose -f compose.yml up -d --build
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

### 6️⃣ Stop and clean up
Stop the experiment stack:
```bash
docker compose -f down
```
Remove volumes (Optional):
```bash
docker compose -f down -v
```

## Experimental Notes
This lab uses **Docker Compose profiles** to enable/disable obfuscation scenarios without duplicating compose files.
- **baseline** (default): WireGuard without obfuscation
- **obfs4** (profile): baseline + obfs4 components enabled
- **udp2raw** (profile): baseline + udp2raw components enabled

Artefacts such as **packet captures (`pcaps/`)** and **experiment outputs (`results/`)** are intentionally excluded from Git.
  Store them locally and only publish sanitised excerpts if needed for documentation.

For reproducibility, image versions should be pinned (no `:latest`). The exact versions used for experiments should be recorded in `.env` (local) and documented in the thesis/report.

Network interfaces for Suricata capture can differ between hosts. If an interface/bridge name is required (e.g. `BRIDGE_IF`),
it should be provided via `.env` or the run script and must not rely on hardcoded defaults.

## Next Steps
1. **Implement profile-based scenarios**
   - Add `profiles: ["obfs4"]` services and adjust routing so baseline traffic can be wrapped via obfs4.
   - Add `profiles: ["udp2raw"]` services and integrate them similarly.

2. **Pin container images**
   - Replace `:latest` with fixed tags (or digests) and document tested versions.

3. **Single entrypoint runner**
   - Add a unified runner script such as:
     - `bash scripts/runs/run_scenario.sh baseline|obfs4|udp2raw`
   - The script should start the correct profile, wait for readiness, generate traffic, and collect artefacts.

4. **Health checks and startup order**
   - Add `healthcheck` to critical services (gateway, suricata, target) and use `depends_on` with health conditions where supported.

5. **Result comparison**
   - Add a small script to compare Suricata outputs across scenarios (baseline vs obfs4 vs udp2raw), e.g. signature counts, alert rate, timing.

6. **Documentation**
   - Add a short architecture diagram and explain where obfuscation is applied in the traffic path for each profile.
