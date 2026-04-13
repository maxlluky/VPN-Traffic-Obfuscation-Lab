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
3. [Traffic Modes](#traffic-modes)
4. [Scenarios](#scenarios)
5. [IDS Validation](#ids-validation)
6. [Inspecting Results](#inspecting-results)
7. [Analysis (Jupyter Notebook)](#analysis-jupyter-notebook)
8. [Cleanup](#cleanup)
9. [Architecture](#architecture)
10. [Advanced Usage](#advanced-usage)
11. [Troubleshooting](#troubleshooting)
12. [Future Work](#future-work--advanced-extensions)
13. [License & Copyright](#copyright)

---


## Project Structure

### Docker Compose Files (`compose/`)
The project uses **multiple compose files** for clarity and modularity, located in the `compose/` directory:

- `compose/compose.yml` – Base configuration (target, suricata, zeek, ndpi, networks)
- `compose/compose.baseline.yml` – Baseline scenario: plain WireGuard
- `compose/compose.udp2raw.yml` – UDP2RAW obfuscation: WireGuard wrapped in TCP/443
- `compose/compose.obfs4.yml` – OBFS4 obfuscation: WireGuard wrapped via Shadowsocks-rust + obfs4proxy (SIP003 plugin)
- `compose/compose.validate.yml` – IDS validation: plain HTTP (no VPN) for positive control

### Scripts (`scripts/`)
```text
scripts/
├── run_scenario.sh        – Main experiment runner (all scenarios + traffic modes)
├── lib.sh                 – Shared functions (stack management, capture, artifact collection)
├── validate_ids.sh        – Detection positive control (proves Suricata, Zeek & nDPI are functional)
├── cleanup.sh             – Tears down all Docker containers, networks, and volumes
└── pcap_to_packet_csv.sh  – Internal: extracts packet features from PCAP via tshark
```

### Services Directory
```text
services/
├── traffic-client/       – Traffic generator (Python script, curl, iperf)
├── target-server/        – Nginx + iperf3 server (pre-installed in Dockerfile)
│   └── html/
├── http-client/          – Validation HTTP client (curl/bind-tools, pre-installed in Dockerfile)
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
├── zeek/                 – NSM (JSON logging)
└── ndpi/                 – DPI (nDPI 5.0, built from source)
```

### Results & Artifacts
```text
results/
├── suricata-alerts/    – Real-time Suricata outputs (eve.json, fast.log)
├── zeek-logs/          – Real-time Zeek JSON logs (conn.log, etc.)
├── ndpi-results/       – Real-time nDPI outputs (summary.txt, flows.csv)
└── runs/
    ├── baseline/       – Baseline experiment results per timestamp
    │   └── <timestamp>/
    │       ├── metadata.json   – Run config: scenario, mode, seed, tool versions
    │       ├── pcap/           – Captured PCAP
    │       ├── pcap_features/  – Tshark-extracted packets.csv
    │       ├── suricata/       – IDS alerts (eve.json, fast.log)
    │       ├── zeek/           – Flow logs (conn.log)
    │       ├── ndpi/           – DPI results (summary.txt, flows.csv)
    │       └── iperf/          – (Streaming mode only) iperf.json
    ├── udp2raw/        – UDP2RAW experiment results
    ├── obfs4/          – OBFS4 experiment results
    └── validation/     – IDS validation results
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
   ```bash
   # Ubuntu/Debian
   sudo apt install tcpdump tshark

   # Arch Linux
   sudo pacman -S tcpdump wireshark-cli
   ```
   > **Note:** nDPI (Deep Packet Inspection) runs as a Docker container — no host installation required.

**Verify Docker:**
```bash
docker --version
docker compose version
```

### 1. Clone the repository
```bash
git clone https://github.com/maxlluky/VPN-Traffic-Obfuscation-Lab.git
cd VPN-Traffic-Obfuscation-Lab
```

### 2. Prepare environment variables
```bash
cp compose/.env.example compose/.env
```
Edit `compose/.env` if required. Key variables:
- `UDP2RAW_IMAGE`: Set this to your local image (e.g., `vpn-lab-udp2raw:latest`) if you built it yourself.
- `ALPINE_TAG`: Use a valid Alpine version (e.g., `3.23`). Ensure the tag exists on Docker Hub.
- `BRIDGE_IF`: Docker bridge interface (auto-detected by scripts, default `br-xxxxxxxxxxxx` in .env is fine).

> Do not commit `compose/.env` — it may contain system-specific configuration.

### 3. Setup WireGuard Configurations
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

### 4. Validate IDS Setup
Before running experiments, verify that Suricata, Zeek and nDPI are working correctly:
```bash
bash scripts/validate_ids.sh
```
This sends plain HTTP traffic (no VPN) and checks for expected alerts. If Suricata reports alerts, Zeek detects HTTP flows, and nDPI identifies HTTP protocol, the detection stack is functional.

### 5. Run your first experiment
```bash
bash scripts/run_scenario.sh baseline
```

---

## Traffic Modes
The experiment scripts support two traffic generation modes, controlled via the second positional argument:

*   **Burst Mode (Default):** Generates 50 sequential HTTP requests (simulating web measurement). Good for testing connectivity and quick alert generation.
*   **Streaming Mode:** Generates a continuous TCP stream for 60 seconds using `iperf3`. Essential for **Long Flow** analysis (Zeek) and connection duration metrics.

**Usage:**
```bash
# Default (Burst)
bash scripts/run_scenario.sh baseline

# Streaming (Recommended for Analysis)
bash scripts/run_scenario.sh baseline streaming

# Run all scenarios sequentially — 1× burst + 2× streaming each (9 runs total)
# Two streaming runs per scenario provide mean ± 95 % CI throughput statistics (t-distribution).
for scenario in baseline udp2raw obfs4; do
  bash scripts/run_scenario.sh "$scenario" burst
  bash scripts/run_scenario.sh "$scenario" streaming
  bash scripts/run_scenario.sh "$scenario" streaming
done
```

---

## Scenarios

### Scenario 1: Baseline (Plain WireGuard)
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
├── metadata.json         – Run config: scenario, mode, seed, tool versions
├── pcap/
│   └── wg-baseline.pcap  – Captured traffic
├── pcap_features/
│   └── packets.csv       – Tshark-extracted packet features
├── suricata/
│   ├── eve.json          – Suricata alerts (JSON)
│   └── fast.log          – Suricata alerts (Text)
├── zeek/
│   ├── conn.log          – Connection logs
│   └── ...
├── ndpi/
│   ├── summary.txt       – Protocol classification summary
│   └── flows.csv         – Per-flow DPI results
└── iperf/                – (Streaming mode only)
    └── iperf.json        – iperf3 throughput results
```

### Scenario 2: UDP2RAW Obfuscation
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

## IDS Validation
Before drawing conclusions from experiment results, run the **positive control** to prove that Suricata, Zeek and nDPI are functional:

```bash
bash scripts/validate_ids.sh
```

**What it does:**
- Starts a minimal stack (Alpine HTTP client + target server, no VPN)
- Sends plain HTTP requests designed to trigger ET Open signatures (curl/wget/Python user-agents, `.exe`/`.bat`/`.ps1` downloads)
- Reports Suricata alerts, Zeek service detections, and nDPI protocol classifications
- Stores artifacts in `results/runs/validation/<timestamp>/`

**Expected outcome:**
- Suricata: Multiple ET POLICY / ET INFO alerts
- Zeek: `conn.log` entries with `service="http"`
- nDPI: Detected protocols including HTTP

This validates that the **absence of alerts in VPN scenarios is a genuine finding**, not a tool misconfiguration.

---

## Inspecting Results

### View Suricata Alerts (JSON)
```bash
jq '.alert | {timestamp, signature, severity}' results/suricata-alerts/eve.json
```

### View Suricata Fast Alerts (Text)
```bash
cat results/runs/baseline/<timestamp>/suricata/fast.log
```

### Analyze pcap with Wireshark
```bash
wireshark results/runs/baseline/<timestamp>/pcap/wg-baseline.pcap &
```

### Compare scenarios
```bash
# Count alerts per scenario
for scenario in baseline udp2raw obfs4; do
  count=$(jq '[.alert] | length' results/runs/$scenario/*/suricata/eve.json | tr -d '\n' | xargs)
  echo "$scenario: $count alerts"
done
```

---

## Analysis (Jupyter Notebook)

### Analysis Guide for Bachelor Thesis
To provide technical depth, focus on **Feature Engineering** using the generated artifacts:

**1. Signature-Based Detection (Suricata)**
- **Metric:** Alert Count & Signature ID.
- **Hypothesis:** Baseline triggers WireGuard signatures; Obfuscated scenarios trigger 0 alerts or generic "TCP" alerts.
- **File:** `suricata/eve.json`
- **Key Fields:** `alert.signature`, `alert.category`, `alert.signature_id`, `payload_printable`.
- **Rule sets loaded:** ET Open (~49 k rules) **+** custom behavioral rules in `services/suricata/rules/local.rules`:
  - SID 9000001 — WireGuard Handshake Initiator: UDP, exact payload 148 B, first 4 bytes `01 00 00 00`
  - SID 9000002 — WireGuard Handshake Response: UDP, exact payload 92 B, first 4 bytes `02 00 00 00`
  These rules detect WireGuard by **packet structure**, not by port number, providing a realistic baseline for behavioral detection.

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

### Requirements
Create a virtual environment and install the necessary Python libraries:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r analysis/requirements.txt
```
> **Note:** Ubuntu 24.04+ requires a virtual environment for pip installs (PEP 668).
> In VS Code, select the `.venv` kernel in the top-right corner of the notebook.

### Running the Analysis
Open the file `analysis/Analysis_Starter.ipynb` in VS Code or JupyterLab.
The notebook performs the following:
1.  **Loads Data:** Automatically discovers all runs in `results/runs/`.
2.  **Suricata Plots:** Visualizes alert counts per scenario, with a stacked breakdown of ET Open vs. custom WireGuard behavioral rule hits (SID 9000001/9000002).
3.  **nDPI Analysis:** Visualizes protocol fingerprinting results and identification rates per scenario.
4.  **Zeek Flows:** Scans `conn.log` to identify tunnel characteristics (Duration vs Bytes).
5.  **Performance (Statistics):** For scenarios run in streaming mode more than once, shows **mean ± 95 % confidence interval** throughput and relative overhead. Individual measurements are overlaid as scatter points. The CI uses the t-distribution (`scipy.stats.t.ppf(0.975, df=n−1)`) rather than the z-approximation, so it is statistically correct for small n (with n = 2 the critical value is 12.706, not 1.96).
6.  **Entropy Calculation:** Parses `.pcap` files payload to compute Shannon Entropy.
7.  **Packet Timing:** Analyzes Inter-Arrival Time (IAT) distribution on a logarithmic scale to detect machine-generated traffic patterns.
8.  **Descriptive Statistics & KS Tests:** Pairwise Kolmogorov-Smirnov tests and descriptive statistics for packet size and IAT.
9.  **Summary Table & Detection Heatmap:** Combined detection effectiveness matrix across all methods (per-column normalised), designed for direct inclusion in the thesis evaluation chapter.

---

## Cleanup

### Quick: Stop current stack
```bash
bash scripts/cleanup.sh
```
This tears down all Docker containers, networks, and volumes created by the lab.

### Full: Also remove built images
```bash
bash scripts/cleanup.sh --all
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
[client_net bridge] ← Suricata/Zeek/nDPI capture point
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
[client_net bridge] ← Suricata/Zeek/nDPI capture point
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
- **Passive Suricata IDS** captures traffic on the client_net bridge (signature-based detection)
- **Zeek NSM** captures behavioral data (conn.log, etc.) on the client_net bridge (flow analysis)
- **nDPI DPI** captures traffic on the client_net bridge (protocol fingerprinting via deep packet inspection)
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
