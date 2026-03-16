<div align="center">
    <img width="234" src="docs/Logo.png"/>
</div>

# VPN Obfuscation Lab (Bachelor Project)
This repository contains a reproducible Docker-based testbed to evaluate the detectability of VPN traffic (baseline WireGuard) and VPN obfuscation techniques (e.g., obfs4, udp2raw) using Suricata IDS, Zeek NSM, and nDPI Deep Packet Inspection.


### Author Information
**Max Luckert**
- **University:** Wrexham University
- **Email:** [S24014929@mail.glyndwr.ac.uk](mailto:S24014929@mail.glyndwr.ac.uk) | [mluckert@outlook.de](mailto:mluckert@outlook.de)

---

## Table of Contents
1. [Project Structure](#project-structure)
2. [Quickstart](#quickstart)
3. [Scenarios](#scenarios)
4. [Inspecting Results](#inspecting-results)
5. [Architecture](#architecture)
6. [Future Work](#future-work--advanced-extensions)
7. [License & Copyright](#copyright)

---


## Project Structure

### Docker Compose Files (`compose/`)
The project uses **multiple compose files** for clarity and modularity, located in the `compose/` directory:

- `compose/compose.yml` – Base configuration (target, suricata, networks)
- `compose/compose.baseline.yml` – Baseline scenario: plain WireGuard
- `compose/compose.udp2raw.yml` – UDP2RAW obfuscation: WireGuard wrapped in TCP/443
- `compose/compose.obfs4.yml` – OBFS4 obfuscation: WireGuard wrapped via Shadowsocks-rust + obfs4proxy (SIP003 plugin)

### Services Directory
```text
services/
├── traffic-client/       – Traffic generator (Python script, curl, iperf)
├── target-server/        – Nginx with static assets
│   └── html/
├── vpn-server/           – WireGuard server configurations
│   ├── baseline/         – Standard MTU config
│   ├── udp2raw/          – Low MTU + sidecar entrypoint.sh
│   └── obfs4/            – Low MTU config
├── vpn-client/           – WireGuard client configurations
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── baseline/         – wg0.conf for Baseline
│   ├── udp2raw/          – wg0.conf for UDP2RAW
│   └── obfs4/            – wg0.conf for OBFS4
├── proxy-obfs4/          – Shadowsocks-rust + obfs4proxy via SIP003 plugin bridge (pt_adapter.py)
├── proxy-udp2raw/        – UDP2RAW proxy (Dockerfile)
├── suricata/             – IDS (uses suricata-update)
└── zeek/                 – NSM (JSON logging)
```

### Results & Artifacts
```text
results/
├── suricata-alerts/    – Real-time IDS outputs (eve.json, fast.log)
├── zeek-logs/          – Real-time Zeek JSON logs (conn.log, etc.)
└── runs/
    ├── baseline/       – Baseline experiment results per timestamp
    │   └── <timestamp>/
    │       ├── pcap/           – Captured PCAP
    │       ├── pcap_features/  – Tshark-extracted packets.csv
    │       ├── suricata/       – IDS alerts (eve.json, fast.log)
    │       ├── zeek/           – Flow logs (conn.log)
    │       ├── ndpi/           – DPI results (summary.txt, flows.csv)
    │       ├── iperf/          – (Streaming mode only) iperf.json
    │       └── metadata.json   – Run config: scenario, mode, seed, tool versions
    ├── udp2raw/        – UDP2RAW experiment results
    └── obfs4/          – OBFS4 experiment results
```

### Analysis Tools (`analysis/`)
Contains Jupyter Notebooks for deep traffic inspection:
- `analysis/Analysis_Starter.ipynb` – Main notebook for visualizing IDS alerts, flow stats, and packet features.
- `analysis/requirements.txt` – Python dependencies.

---

## Quickstart

### Prerequisites
1. Linux host (tested with Ubuntu / Arch Linux)
2. Docker Engine ≥ 24.x
3. Docker Compose v2
4. Kernel support for WireGuard (`wireguard`, `udp_tunnel`)

5. `bash`, `tcpdump`, `tshark` (required for packet capture and feature extraction)
6. `ndpiReader` (required for Deep Packet Inspection analysis)
   ```bash
   # Ubuntu/Debian
   sudo apt install tcpdump tshark libndpi-bin

   # Arch Linux
   sudo pacman -S tcpdump wireshark-cli ndpi
   ```

**Verify Docker:**
```bash
docker --version
docker compose version
```

### 1️⃣ Clone the repository
```bash
git clone https://github.com/maxlluky/VPN-Traffic-Obfuscation-Lab.git
cd VPN-Traffic-Obfuscation-Lab
```

### 2️⃣ Prepare environment variables
```bash
cp compose/.env.example compose/.env
```
Edit `compose/.env` if required. Key variables:
- `UDP2RAW_IMAGE`: Set this to your local image (e.g., `vpn-lab-udp2raw:latest`) if you built it yourself.
- `ALPINE_TAG`: Use a valid Alpine version (e.g., `3.23`). Ensure the tag exists on Docker Hub.
- `BRIDGE_IF`: Docker bridge interface (auto-detected by scripts, default `br-xxxxxxxxxxxx` in .env is fine).

> ⚠️ Do not commit `compose/.env` — it may contain system-specific configuration.

### 3️⃣ Setup WireGuard Configurations
**Note:** The `wg0.conf` configuration files are now included in the repository for the lab environment. You generally **do not** need to copy templates unless you want to generate new keys.

If you *do* need to reset keys:
1. **Copy the templates:**
   ```bash
   cp services/vpn-client/baseline/wg0.conf.template services/vpn-client/baseline/wg0.conf
   cp services/vpn-client/udp2raw/wg0.conf.template services/vpn-client/udp2raw/wg0.conf
   cp services/vpn-client/obfs4/wg0.conf.template services/vpn-client/obfs4/wg0.conf
   ```

2. **Fill in your keys:**
   Open each `wg0.conf` file and replace the placeholders (`<YOUR_CLIENT_PRIVATE_KEY>`, `<SERVER_PUBLIC_KEY>`, etc.) with the actual keys from your WireGuard server setup.

   *Note: Ensure `AllowedIPs` in the client configs matches the lab network (e.g., `172.30.30.0/24`) and the `Endpoint` points to the correct gateway (192.168.10.2:51820 for baseline) or the local tunnel (127.0.0.1:51820 for obfuscated scenarios).*

---

## Traffic Modes
The experiment scripts support two traffic generation modes, controlled via the `TRAFFIC_MODE` environment variable:

*   **Burst Mode (Default):** Generates 50 sequential HTTP requests (simulating web measurement). Good for testing connectivity and quick alert generation.
*   **Streaming Mode:** Generates a continuous TCP stream for 60 seconds using `iperf3`. Essential for **Long Flow** analysis (Zeek) and connection duration metrics.

**Usage:**
```bash
# Default (Burst)
bash scripts/run_scenario.sh baseline

# Streaming (Recommended for Analysis)
TRAFFIC_MODE=streaming bash scripts/run_scenario.sh baseline

# Run all scenarios sequentially
for scenario in baseline udp2raw obfs4; do
  bash scripts/run_scenario.sh "$scenario"
done
```

## Scenarios

### Scenario 1: Baseline (Plain WireGuard)
Run the baseline WireGuard experiment without obfuscation:

```bash
bash scripts/run_scenario.sh baseline
```

**What it does:**
- Starts `compose/compose.yml` + `compose/compose.baseline.yml`
- Captures UDP/51820 (WireGuard) packets
- Generates HTTP traffic through the VPN
- Collects Suricata IDS alerts, Zeek logs, and nDPI protocol classifications
- Stores artifacts in `results/runs/baseline/<timestamp>/`

**Output files:**
```text
results/runs/baseline/<dd-mm-yyyy-hh-mm-ss>/
├── pcap/
│   └── wg-baseline.pcap  – Captured traffic
├── suricata/
│   ├── eve.json          – Suricata alerts (JSON)
│   └── fast.log          – Suricata alerts (Text)
├── zeek/
│   ├── conn.log          – Connection logs
│   └── ...
└── ndpi/
    ├── summary.txt       – Protocol classification summary
    └── flows.csv         – Per-flow DPI results
```

### Scenario 2: UDP2RAW Obfuscation
Run the UDP2RAW obfuscation experiment (WireGuard wrapped in TCP/443):

```bash
bash scripts/run_scenario.sh udp2raw
```

**What it does:**
- Starts `compose/compose.yml` + `compose/compose.udp2raw.yml`
- Wraps WireGuard (UDP/51820) in TCP/443 using udp2raw
- Gateway unwraps TCP → UDP and forwards to WireGuard
- Client unwraps UDP ← TCP from the gateway
- Captures TCP/443 packets
- Generates HTTP traffic through the VPN
- Collects Suricata IDS alerts, Zeek logs, and nDPI protocol classifications
- Stores artifacts in `results/runs/udp2raw/<timestamp>/`

**Network topology:**
```text
[client-node] → [udp2raw-client] → (TCP/443) → [udp2raw-gateway] → [gateway/WireGuard]
```

### Scenario 3: OBFS4 Obfuscation
Run the OBFS4 obfuscation experiment:

```bash
bash scripts/run_scenario.sh obfs4
```

**What it does:**
- Starts `compose/compose.yml` + `compose/compose.obfs4.yml`
- Uses **Shadowsocks-rust** (with `-U` UDP relay) and **obfs4proxy** as a SIP003 plugin via `pt_adapter.py`
- Client: `sslocal` receives WireGuard UDP/51820, encrypts with ChaCha20-Poly1305, and applies obfs4 obfuscation
- Gateway: `ssserver` unwraps obfs4 → decrypts Shadowsocks → forwards WireGuard UDP/51820
- Traffic on the wire is **UDP** on port `${OBFS4_PORT}` (default 12345) with randomised obfs4 payload
- Captures OBFS4 traffic (UDP port configured in `.env`)
- Generates HTTP traffic through the VPN
- Collects Suricata IDS alerts, Zeek logs, and nDPI protocol classifications
- Stores artifacts in `results/runs/obfs4/<timestamp>/`

---

## Inspecting Results

### View Suricata Alerts (JSON)
```bash
jq '.alert | {timestamp, signature, severity}' results/suricata-alerts/eve.json
```

### View Suricata Fast Alerts (Text)
```bash
cat results/runs/baseline/<timestamp>/fast.log
```

### Analyze pcap with Wireshark
```bash
wireshark results/runs/baseline/<timestamp>/wg-baseline.pcap &
```

### Compare scenarios
```bash
# Count alerts per scenario
for scenario in baseline udp2raw obfs4; do
  count=$(jq '[.alert] | length' results/runs/$scenario/*/eve.json | tr -d '\n' | xargs)
  echo "$scenario: $count alerts"
done
```

---

## Analysis Guide for Bachelor Thesis
To provide technical depth, focus on **Feature Engineering** using the generated artifacts:

**1. Signature-Based Detection (Suricata)**
- **Metric:** Alert Count & Signature ID.
- **Hypothesis:** Baseline triggers WireGuard signatures; Obfuscated scenarios trigger 0 alerts or generic "TCP" alerts.
- **File:** `suricata/eve.json`
- **Key Fields:** `alert.signature`, `alert.category`, `payload_printable`.

**2. Flow Analysis (Zeek)**
- **Metric:** Flow Duration, Bytes Transferred (Ratio), inter-arrival times.
- **Hypothesis:** VPN tunnels show long durations and high byte counts compared to normal web browsing.
- **File:** `zeek/conn.log`
- **Key Fields:**
    - `id.orig_h` / `id.resp_h`: Source/Dest IP.
    - `proto`: Protocol (UDP for WireGuard, TCP for obfuscation).
    - `service`: Detected application (e.g., "ssl", "http", or "-").
    - `orig_bytes` / `resp_bytes`: Volume of data (Tunneling = high volume).
    - `duration`: Length of connection.

**3. Deep Packet Inspection (nDPI)**
- **Metric:** Protocol identification rate (percentage of flows correctly classified).
- **Hypothesis:** nDPI identifies baseline WireGuard but fails on well-obfuscated traffic (obfs4). UDP2RAW may be misclassified as TLS.
- **File:** `ndpi/summary.txt` and `ndpi/flows.csv`
- **Key Fields:** Detected protocol name, confidence level, flow count per protocol.

**4. Entropy & Payload Analysis (PCAP)**
- **Metric:** Shannon Entropy of payload bytes.
- **Hypothesis:** Encrypted WireGuard traffic has high entropy (close to 8.0). Obfuscated traffic (like obfs4) also has high entropy but attempts to look random.
- **Tooling:** Use python `scapy` or `pandas` to calculate entropy on `pcap/` files.

## 5. Analysis Implementation (Jupyter Notebook)
To perform the analysis described above, use the provided Jupyter Notebook template:

### 1. Requirements
Create a virtual environment and install the necessary Python libraries:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r analysis/requirements.txt
```
> **Note:** Ubuntu 24.04+ requires a virtual environment for pip installs (PEP 668).
> In VS Code, select the `.venv` kernel in the top-right corner of the notebook.

### 2. Running the Analysis
OPEN the file `analysis/Analysis_Starter.ipynb` in VS Code or JupyterLab.
The notebook performs the following:
1.  **Loads Data:** Automatically discovers the latest runs in `results/runs/`.
2.  **Suricata Plots:** Visualizes alert counts per scenario (to show efficacy of obfuscation).
3.  **nDPI Analysis:** Visualizes protocol fingerprinting results and identification rates per scenario.
4.  **Zeek Flows:** Scans `conn.log` to identify tunnel characteristics (Duration vs Bytes).
5.  **Entropy Calculation:** Parses `.pcap` files payload to compute Shannon Entropy.
6.  **Packet Timing:** Analyzes Inter-Arrival Time (IAT) distribution on a logarithmic scale to detect machine-generated traffic patterns.
7.  **Detection Heatmap:** Combined detection effectiveness matrix across all methods (per-column normalised).

---

## Cleanup

### Stop current stack
```bash
docker compose -f compose/compose.yml -f compose/compose.baseline.yml down
# or
docker compose -f compose/compose.yml -f compose/compose.udp2raw.yml down
# or
docker compose -f compose/compose.yml -f compose/compose.obfs4.yml down
```

### Remove all containers and networks
```bash
docker compose -f compose/compose.yml -f compose/compose.baseline.yml down -v
docker compose -f compose/compose.yml -f compose/compose.udp2raw.yml down -v
docker compose -f compose/compose.yml -f compose/compose.obfs4.yml down -v
```

### Clean experiment results (optional)
```bash
sudo rm -rf results/runs/* results/suricata-alerts/*
```

---

## Architecture

### Network Topology
![Architecture Diagram](docs/Architecture-diagram.png)

The testbed uses two isolated Docker networks:

- **`client_net` (192.168.10.0/24)** – VPN client-side network
- **`external_net` (172.30.30.0/24)** – External / target network
- **`internal_net` (192.168.20.0/24)** – Internal network for obfuscation proxies (UDP2RAW & OBFS4 only)

### Traffic Flow: Baseline
```text
client-node (192.168.10.10)
    ↓
wg-client (WireGuard UDP/51820)
    ↓
vpn-gateway (192.168.10.2 ↔ 172.30.30.2)
    ↓
target-server (172.30.30.10)
```

### Traffic Flow: UDP2RAW
```text
client-node (192.168.10.10)
    ↓
wg-client (127.0.0.1:51820)
    ↓
udp2raw-client (unwraps TCP/443 → UDP/51820)
    ↓ (TCP/443)
[client_net bridge] ← Suricata/Zeek capture point
    ↓ (TCP/443)
udp2raw-gateway (wraps TCP/443 → UDP/51820)
    ↓
vpn-gateway (WireGuard UDP/51820)
    ↓
target-server (172.30.30.10)
```

### Traffic Flow: OBFS4 (Shadowsocks-rust + obfs4proxy SIP003)
```text
client-node (192.168.10.10)
    ↓ (HTTP requests)
wg-client (127.0.0.1:51820)
    ↓ (WireGuard UDP/51820 → loopback)
obfs4-client [sslocal -U + pt_adapter.py + obfs4proxy]
    ↓ (Shadowsocks ChaCha20 + obfs4 randomisation, UDP/${OBFS4_PORT})
[client_net bridge] ← Suricata/Zeek capture point
    ↓ (obfuscated UDP)
obfs4-gateway [ssserver + pt_adapter.py + obfs4proxy]
    ↓ (unwraps obfs4 → decrypts Shadowsocks → UDP/51820)
vpn-gateway (WireGuard UDP/51820)
    ↓
target-server (172.30.30.10)
```

> **Note:** Unlike standard Tor obfs4 (which uses TCP), this setup uses Shadowsocks-rust's
> `-U` flag for UDP relay mode. The obfs4 obfuscation layer is applied via the SIP003 plugin
> specification (`pt_adapter.py` bridges Shadowsocks ↔ obfs4proxy). The outer transport
> visible on the wire is therefore **UDP**, not TCP.

### Design Rationale
- **Separate compose files** ensure clarity: base + scenario-specific overrides
- **Identical client-node** across all scenarios guarantees the same application traffic
- **Automatic bridge detection** eliminates hardcoded interface names
- **Passive Suricata IDS** captures traffic on the external_net bridge (signature-based detection)
- **Zeek NSM** captures behavioral data (conn.log, etc.) on the external_net bridge (flow analysis)
- **nDPI** performs offline Deep Packet Inspection on the captured PCAP (protocol fingerprinting)
- **tcpdump** captures raw packets independently of Suricata

---

## Advanced Usage

### Run with custom parameters
```bash
# Generate 100 HTTP requests instead of 50
HTTP_REQUESTS=100 bash scripts/run_scenario.sh baseline

# Capture for longer (keep tcpdump running for 5 extra seconds after traffic)
TCPDUMP_SECONDS_TAIL=5 bash scripts/run_scenario.sh baseline
```

### Inspect container logs
```bash
# View WireGuard logs (baseline)
docker logs vpn-gateway

# View UDP2RAW logs
docker logs udp2raw-gateway
docker logs udp2raw-client

# View OBFS4 logs
docker logs obfs4-gateway
docker logs obfs4-client

# View Suricata logs
docker logs suricata-ids
```

### Rebuild a specific service
```bash
docker compose -f compose/compose.yml -f compose/compose.udp2raw.yml up -d --build wg-client
```

---

## Troubleshooting

### Bridge interface not found
If you see: `Bridge interface 'br-xxxx' not found on host`

Run the experiment script again, or manually set `BRIDGE_IF`:
```bash
BRIDGE_IF=br-a1b2c3d4e5f6 bash scripts/run_scenario.sh baseline
```

### Suricata not starting
Check logs:
```bash
docker logs suricata-ids
```

Ensure `BRIDGE_IF` is set correctly in `.env`.

### WireGuard connection fails in UDP2RAW scenario
- Verify UDP2RAW containers are running: `docker ps | grep udp2raw`
- Check logs: `docker logs udp2raw-gateway` and `docker logs udp2raw-client`
- Ensure `UDP2RAW_GATEWAY_PORT=443` is accessible

### OBFS4 connection fails
- Verify OBFS4 containers are running: `docker ps | grep obfs4`
- Check Shadowsocks + obfs4proxy logs: `docker logs obfs4-gateway` and `docker logs obfs4-client`
- Verify the SIP003 plugin bridge (`pt_adapter.py`) started correctly in both containers
- Ensure the obfs4 cert and shared password match between client and gateway

---

## Contributing
This is a Bachelor project. **Contributions are currently NOT accepted.**
Please do not open Pull Requests until the project is officially marked as completed (expected: May 2026).

Once the project is finished, contributions will be welcome!

Please ensure:
- Scripts are POSIX-compliant
- Docker Compose files validate: `docker compose config`
- Results are excluded from Git (see `.gitignore`)

---

## Future Work & Advanced Extensions

### 1. Behavior-Based Detection (Machine Learning)
*Note: The findings of this analysis point towards the necessity of Machine Learning for detecting obfuscated flows. This section discusses the theoretical application of such methods as a countermeasure.*

While the current work covers **Feature Engineering** (Entropy, IAT), a logical extension is the application of **Machine Learning models** (Random Forest, SVM, CNN) trained on these extracted features.

**Theoretical Approach:**
- **Feature Extraction:** Use flow-level features (duration, packet counts, bytes) and time-series data (inter-arrival times) identified in this lab.
- **Classification:** Train models to distinguish between "Web Browsing" and "Obfuscated VPN" based on the statistical anomalies preserved by the obfuscation tools (e.g., specific burst patterns in UDP2RAW).
- **Goal:** To overcome the limitations of signature-based detection (Suricata) demonstrated in this project.

---

## Copyright
The contents and works in this software created by the software operators are subject to German copyright law. The reproduction, editing, distribution and any kind of use outside the limits of copyright law require the written consent of the respective author or creator. Downloads and copies of this software are only permitted for private, non-commercial use.

Insofar as the content on this software was not created by the operator, the copyrights of third parties are observed. In particular, third-party content is identified as such. Should you nevertheless become aware of a copyright infringement, please inform us accordingly. If we become aware of any infringements, we will remove such contents immediately.
Source: [eRecht24.de](https://www.e-recht24.de/)
