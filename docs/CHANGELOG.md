# Lab Notes

## 2026-03-25
### Added
- **nDPI Live Container (`services/ndpi/`):** nDPI now runs as a live Docker container alongside Suricata and Zeek on the bridge interface, replacing the previous offline `ndpiReader` host invocation. Built from source (nDPI 5.0) using a multi-stage Alpine build (~42 MB image). All three detection tools now share the same live capture architecture.
    - New `services/ndpi/Dockerfile` — multi-stage Alpine build compiling nDPI 5.0 from source.
    - New `services/ndpi/entrypoint.sh` — writes version metadata, starts `ndpiReader` in live capture mode. Translates SIGTERM→SIGINT via trap so `docker stop` triggers a clean flush of summary and flow data (ndpiReader ignores SIGTERM but responds to SIGINT).
    - New `ndpi` service in `compose/compose.yml` — host networking, `NET_ADMIN`/`NET_RAW` capabilities, logs to `results/ndpi-results/`.
    - `lib.sh`: Added `NDPI_LOG_DIR`, updated `reset_ids_logs()` and `collect_artifacts()` to manage nDPI container lifecycle and collect live results.
    - `validate_ids.sh`: Updated to stop nDPI container, collect and display nDPI protocol detection results.
    - `ndpiReader` no longer required on the host — removed from README prerequisites.

### Fixed
- **Suricata `EXTERNAL_NET` Configuration (`suricata.yaml`):** Changed `EXTERNAL_NET` from `"!$HOME_NET"` to `"any"`. In the lab topology all traffic runs between private IPs (192.168.10.x ↔ 192.168.10.x), which are all in `HOME_NET`. ET Open rules matching `$HOME_NET -> $EXTERNAL_NET` could never fire because `EXTERNAL_NET` excluded all private ranges. With `"any"`, rules now match regardless of IP scope. **All previous runs were affected — rules that should have matched HOME→HOME traffic were silently skipped.**
- **`validate_ids.sh` Alert Display Bug:** Alert signatures were captured into a variable but never printed to the terminal. Additionally, the "no alerts" check compared the formatted text output to `"0"`, which never matched. Replaced with direct stdout output from Python and `sys.exit(1)` to trigger the warning on zero alerts.
- **`metadata.json` Not Generated (SIGPIPE crash):** `ndpiReader --version` outputs a large help text; `head -1` closed the pipe, causing SIGPIPE (exit 141) which `set -euo pipefail` treated as fatal. All code after this line was silently skipped. Fixed by extracting the version from the already-written `summary.txt` instead.
- **`vpn-client/Dockerfile` Unpinned Alpine:** Used `alpine:latest` instead of `alpine:${ALPINE_TAG}`. Now pinned via build arg for reproducibility.
- **Suricata Dockerfile Unpinned Base Image:** Used `jasonish/suricata:latest` instead of `${SURICATA_IMAGE}` from `.env`. Now uses `ARG SURICATA_IMAGE` for version pinning.
- **Unused `OBFS4_IMAGE` in `.env`:** Removed — obfs4 containers are built locally, this variable was never referenced.
- **Analysis Notebook `flows.csv` Delimiter:** Added explicit `sep='|'` to `pd.read_csv()` for nDPI flows.csv parsing. ndpiReader uses pipe delimiters, not commas — previously worked by coincidence but was fragile.

### Changed
- **`run_scenario.sh` Terminal Banner:** Added visual header (scenario, traffic mode, run directory) and footer (completion summary) using box-drawing characters, consistent with `validate_ids.sh` style.
- **README Overhaul:** Restructured and expanded documentation:
    - Added `scripts/` directory listing with all scripts and their purpose.
    - Added dedicated **IDS Validation** section documenting `validate_ids.sh` usage and expected outcomes.
    - Replaced manual `docker compose down` instructions in **Cleanup** section with `scripts/cleanup.sh` usage.
    - Added `compose.validate.yml` to compose file listing.
    - Added `validation/` to results directory tree.
    - Updated Table of Contents to match new section structure.
    - Corrected Suricata/Zeek capture point references from "external_net" to "client_net" in Design Rationale.
    - Fixed file paths in "Inspecting Results" examples (added `suricata/` and `pcap/` subdirectories).

## 2026-03-24
### Changed
- **`run_scenario.sh` CLI:** Traffic mode is now accepted as an optional second positional argument (`bash scripts/run_scenario.sh baseline streaming`) instead of requiring an environment variable prefix (`TRAFFIC_MODE=streaming`). The environment variable is still supported as a fallback for backwards compatibility.
- **`run_scenario.sh` Output:** Now displays the active traffic mode (`burst` / `streaming`) alongside the scenario label at startup.
- **`run_scenario.sh` COMPOSE_OVERRIDE:** All three scenarios (including baseline) now consistently allow override via the `COMPOSE_OVERRIDE` environment variable.
- **README:** Updated usage examples, Traffic Modes description, and output file tree to reflect new CLI syntax and complete artifact structure (added `metadata.json`, `pcap_features/`, `iperf/`).
- **`iperf_output.json` Path:** iperf3 results are now written directly to `$RUN_DIR/iperf/iperf.json` during traffic generation instead of being temporarily placed in the repository root and moved later.

### Added
- **`print_progress()` Helper (`lib.sh`):** Unified progress bar function used by both streaming and packet extraction. Uses ANSI `\033[2K` line-clear escape, 30-char bar width (fits 80-column terminals), and 0–100% clamping.
- **`extract_packet_features()` Function (`lib.sh`):** Extracted PCAP feature extraction into its own function with progress bar. Uses `capinfos` for fast packet counting (header-only read) with `tshark` fallback.

### Fixed
- **`metadata.json` nDPI Fields Always "N/A":** `metadata.json` was generated before nDPI analysis ran, so `ndpi_protocol` and nDPI version were always "N/A". Moved metadata generation to the end of `collect_artifacts()`, after all data is available.
- **Suricata Version Always "Unknown":** Version was queried after the container was already stopped. Moved version detection before `docker stop`.
- **Progress Bar Line Duplication:** Both streaming and packet extraction progress bars created new lines instead of updating in-place. Root causes: (1) background `pcap_to_packet_csv.sh` echo output interleaved with `\r` overwrites, (2) progress bar lines exceeded 80 columns causing terminal wraps. Fixed by suppressing background script output (`>/dev/null 2>&1`) and reducing bar width from 50 to 30 characters.
- **Streaming Progress Bar Dead Code:** The `if docker exec ... & then / else` pattern always succeeded (backgrounding returns 0), making the `else` branch unreachable. Replaced with direct backgrounding and `wait || log WARNING`.
- **`detect_network_info()` Used Global Instead of Parameter:** Target IP resolution used `$TARGET_CONTAINER` (global) instead of `$target_container` (function parameter). Fixed to use the local parameter consistently.

### Removed
- **Redundant `run_info.json`:** Removed from `run_scenario.sh`. The same data (`traffic_mode`) is already written to `metadata.json`.
- **Redundant `TRAFFIC_MODE` Default in `lib.sh`:** Removed fallback assignment in `generate_traffic()` since `run_scenario.sh` already validates and exports the variable.

## 2026-03-16
### Added
- **nDPI Deep Packet Inspection (`lib.sh`):** `collect_artifacts()` now automatically runs `ndpiReader` against captured PCAPs, producing per-flow protocol classification (`flows.csv`) and a detection summary (`summary.txt`) as run artifacts. Protocol and version are also written into `metadata.json`.
- **Analysis Notebook, nDPI Section (2b):** New section visualising nDPI protocol fingerprinting results per scenario, includes protocol classification bar chart and detection effectiveness matrix.
- **Thesis DPI Integration Guide (`docs/THESIS_DPI_INTEGRATION_GUIDE.md`):** Chapter-by-chapter reference for integrating DPI into the written thesis, including required source searches, new metrics, and effort estimates.

### Changed
- **Analysis Notebook, Detection Heatmap:** Switched from a global 0 to 100 colour scale to per-column normalisation. This ensures metrics with different ranges (nDPI 0 to 100%, Entropy Gap 6 to 8%) are visually distinguishable while raw values remain annotated.
- **README:** Updated project description, artefact structure, scenario outputs, and analysis guide to reflect nDPI as the third detection layer alongside Suricata and Zeek.

## 2026-03-15
### Fixed
- **Suricata Rule Configuration:** Changed `suricata.yaml` to load `suricata.rules` (ET Open ruleset, ~42,400 signatures) instead of only `local.rules` (3 custom port-based rules). Previous configuration meant Suricata was not using the ET Open ruleset for detection, undermining the thesis evaluation of signature-based IDS effectiveness.
- **Custom Rules Removed:** Cleared `local.rules` of the three simplistic port-matching rules (SID 1000002–1000004) that triggered on any traffic to ports 51820, 443, and 12345 regardless of protocol content.
- **Suricata Variable Definitions:** Added all required `port-groups` (`$HTTP_PORTS`, `$SSH_PORTS`, `$SHELLCODE_PORTS`, etc.) and `address-groups` (`$HTTP_SERVERS`, `$SMTP_SERVERS`, etc.) to `suricata.yaml`. Without these, ~6,700 ET Open rules silently failed to parse — raising active rules from ~42,400 to ~49,085. **All previous scenario runs had incomplete Suricata detection.**
- **README OBFS4 Protocol Correction:** Fixed two references incorrectly stating OBFS4 uses TCP. The OBFS4 scenario uses **UDP** transport (shadowsocks-rust `-U` flag enables UDP relay mode via SIP003/obfs4proxy).
- **README OBFS4 Architecture Documentation:** The README previously only mentioned "obfs4proxy" without explaining the full stack. Updated compose file descriptions, services directory listing, Scenario 3 details, traffic flow diagram, and troubleshooting section to clearly document that OBFS4 runs as a **Shadowsocks-rust SIP003 plugin** (`sslocal`/`ssserver` + `pt_adapter.py` + `obfs4proxy`) with ChaCha20-Poly1305 encryption over UDP.

### Added
- **IDS Validation Script (`scripts/validate_ids.sh`):** Positive control that sends plain HTTP traffic to prove Suricata and Zeek are functional. Validates that the absence of alerts in VPN scenarios is a genuine finding, not a tool misconfiguration.
- **Suricata Engine Readiness Wait (`lib.sh`):** Added `wait_for_suricata()` function that polls for Suricata's "engine started" log message (up to 60s) before sending traffic. Integrated into `reset_ids_logs()` to prevent traffic generation before rule parsing completes.
- **Cleanup Script (`scripts/cleanup.sh`):** New utility to tear down all Docker containers, networks, and volumes created by the lab. Supports `--all` flag to also remove built images.
- **Analysis Notebook — Shannon Entropy (Section 6):** Per-packet entropy calculation from raw PCAP payloads via tshark. Includes KDE distribution plot and entropy-vs-packet-size scatter plot.
- **Analysis Notebook — Descriptive Statistics & KS Tests (Section 7):** Packet size and IAT descriptive statistics (mean, median, std, IQR, percentiles). Pairwise Kolmogorov-Smirnov tests for packet size and IAT distributions across all scenarios.
- **Analysis Notebook — Summary Table & Detection Heatmap (Section 8):** Consolidated results matrix (Scenario × Metric) for thesis evaluation chapter. Includes detection effectiveness heatmap.

### Removed
- **Wrapper Scripts:** Deleted `run_baseline.sh`, `run_obfs4.sh`, `run_udp2raw.sh`. All scenarios are now run exclusively via `scripts/run_scenario.sh <scenario>`.
- **README:** Updated all references from deleted wrapper scripts to `run_scenario.sh`.

### Changed
- **Analysis Notebook — IAT Visualisation:** Replaced boxplot with violin plot for better distribution visibility.
- **Analysis Notebook — Overview:** Corrected source count ("four" → "five"), added ET Open and Shannon Entropy references.
- **Analysis Notebook — Protocol Plausibility:** Fixed SettingWithCopyWarning, added fallback message for scenarios without port 443 traffic.

## 2026-03-10
### Fixed
- **Repository Setup (Fresh Clone):** Confirmed that `cp compose/.env.example compose/.env` is the only required manual step after cloning. All WireGuard key pairs were cryptographically verified (Curve25519) — all three scenarios correct.
- **Kernel Module Issue (Arch Linux):** Resolved Docker networking failure (`veth` module not found) caused by a kernel update without reboot. Running kernel (`6.18.9`) did not match installed modules (`6.19.6`). Fixed by rebooting into the updated kernel.
- **README Clone URL:** Corrected the `git clone` URL from the outdated `vpn-lab.git` to the correct `VPN-Traffic-Obfuscation-Lab.git`.
- **README Architecture Diagrams:** Updated all three traffic flow diagrams to use current container names (`vpn-gateway`, `target-server`) and added capture point annotations.

### Changed
- **`.gitignore`:** Added exclusions for two auto-generated file types that should never be committed:
    - `services/suricata/rules/suricata.rules` — downloaded fresh at container build time by `suricata-update` (~43 MB, changes with every ET Open release).
    - `**/templates/peer.conf` and `**/templates/server.conf` — generated at runtime by the `linuxserver/wireguard` image; irrelevant since static `wg_confs/wg0.conf` is used.
- **`docs/CHANGELOG.md`:** Backfilled missing entries for the service rename refactor (2026-02-04) and `run_scenario.sh` consolidation (2026-02-26).

### Verified
- All three scenarios (Baseline, UDP2RAW, OBFS4) run successfully end-to-end on Arch Linux after fresh clone.

## 2026-02-26
### Changed
- **Project Structure:** Refactored and simplified the repository structure for better maintainability and clarity.
- **VPN Configurations:** Updated baseline WireGuard configurations to ensure out-of-the-box functionality.
- **Script Consolidation:** Merged scenario execution logic into a new unified `scripts/run_scenario.sh`. The existing `run_baseline.sh`, `run_udp2raw.sh`, and `run_obfs4.sh` scripts are now thin wrappers that delegate to it. Eliminates code duplication and centralises all experiment parameters.

### Fixed
- **WireGuard Handshake Synchronization:** Synchronized static public/private key pairs across the baseline WireGuard configurations (`services/vpn-client/baseline/wg0.conf` and `services/vpn-server/baseline/wg_confs/wg0.conf`) to ensure reliable end-to-end tunnel establishment.
- **Static Configuration Persistence:** Refined the Docker Compose environment parameters by removing the `PEERS` auto-generation variable. This guarantees that the `linuxserver/wireguard` containers retain the predefined static `wg0.conf` topologies instead of dynamically overwriting them on boot.
- **OBFS4 Routing and Protocol Robustness:** Enhanced the OBFS4 Python bridge (`pt_adapter.py`) by implementing case-insensitive protocol handshake parsing, preventing `IndexError` exceptions during SOCKS5 negotiation. Furthermore, updated the `TARGET_HOST` routing definitions in `obfs4-client` to smoothly align with the recent `vpn-gateway` container renaming, fully restoring Shadowsocks UDP-to-TCP encapsulation.
- **Artifact Pipeline Permissions:** Assigned correct write permissions for the `lab-admin` user on the `results/` telemetry folder, ensuring seamless automated report generation during scenario testing.

### Docs
- Removed redundant alternative command examples from README to reduce clutter.

## 2026-02-04 / 2026-02-05
### Added
- **Realistic Traffic Generation:**
    - Created `services/client/traffic_gen.py` Python script for seeded, weighted HTTP traffic.
    - Supports weighted selection (HTML vs. large binaries), randomized think-time, and reproducibility via `--seed`.
    - Installed Python3 and `py3-requests` in the client Dockerfile.
- **Data Pipeline Enhancements:**
    - `scripts/pcap_to_packet_csv.sh`: Extracts packet-level features (size, timing, flags) via Tshark to `packets.csv`.
    - `metadata.json` generated per run: Contains scenario, mode, seed, and exact tool versions (Suricata, Zeek, Tshark).
- **Suricata Rule Management:**
    - Custom `services/suricata/Dockerfile` and `entrypoint.sh` to run `suricata-update` and load ET Open rules.
    - Logs loaded rule count in `suricata_meta.json`.
- **Zeek JSON Logging:**
    - Created `services/zeek/local.zeek` policy to enable JSON output for `conn.log`.
- **Target Server Assets:**
    - Created `services/target/html/index.html` and dummy binary assets (50KB, 200KB, 1MB) for realistic burst traffic.

### Changed
- **Project Structure Refactoring:**
    - Reorganized `services/gateway/` into scenario-specific directories: `wireguard/` (Standard), `udp2raw/`, `obfs4/`.
    - Each obfuscation scenario now has its own WireGuard config with lowered MTU (1200) to prevent packet fragmentation issues.
    - Updated all `compose.*.yml` files to reference the new structure.
- **Analysis Notebook:**
    - Completely rewrote `Analysis_Starter.ipynb` to use the new data formats (JSON Zeek logs, `packets.csv`, `metadata.json`).
    - Notebook now has 4 sections: Run Metadata, IDS Visibility, Traffic Fingerprinting, Performance.
- **User Feedback:**
    - Added `flush=True` to Python traffic generator and run with `python3 -u` for real-time output.
    - iPerf directory is now only created if iperf produces output (Streaming mode).

### Fixed
- **UDP2RAW & OBFS4 Stability:**
    - Resolved timeouts for large file downloads by setting `MTU = 1200` in WireGuard configs for obfuscation scenarios.
- **Obsolete Files:**
    - Cleaned auto-generated files (`peer_client1/`, `server/`, etc.) from `services/gateway/udp2raw`.

### Changed
- **Service Renaming for Clarity:** Renamed all Docker Compose services to more descriptive names to improve readability across compose files, scripts, and logs:
    - `client` → `traffic-client`
    - `target` → `target-server`
    - `gateway` → `vpn-server`
    - `wg-client` → `vpn-client`
    - `obfs4` → `proxy-obfs4`
    - `udp2raw` → `proxy-udp2raw`


## 2026-01-26
- Created Ubuntu Server 24.04.3 LTS VM (lab-host) on Windows 11 host.
- Enabled SSH administration.
- Initialised git repository and baseline folder structure.


## 2026-01-27
### Added
- Reproducible baseline experiment automation script
- Automatic resolution of target container IP per run
- Timestamped run directories for experimental artefacts
- Parallel packet capture of encrypted WireGuard traffic
- Clean per-run Suricata log handling (fast.log, eve.json)

### Changed
- Improved experiment structure to separate setup, execution, and results

## 2026-01-30

### Added
- **Multi-profile Docker Compose architecture**
  - Refactored monolithic `compose.yml` into modular base + scenario overrides.
  - Scenarios: `compose.baseline.yml`, `compose.udp2raw.yml`, `compose.obfs4.yml`.
- **Obfuscation Scenarios (UDP2RAW & OBFS4)**
  - Full support for UDP2RAW (TCP/443 wrapping) and OBFS4 (obfs4 protocol).
  - Dedicated build contexts and automation scripts (`run_udp2raw.sh`, `run_obfs4.sh`).
- **WireGuard Configuration Templates**
  - Added `wg0.conf.template` files for all scenarios to simplify setup.
- **Enhanced Configuration & Documentation**
  - Sectioned `.env` with new variables for obfuscation ports and images.
  - Rewrote README.md with diagrams, setup steps, and troubleshooting.

### Changed
- **Project Structure Refactor**
  - Centralized all compose and env files into the `compose/` directory.
  - Updated all run scripts to reference the new paths.
  - Reorganized `services/` directory for better modularity.

### Fixed
- **Environment & Build**
  - Corrected `ALPINE_TAG` to `3.23` and set `UDP2RAW_IMAGE` to local default.
  - Adjusted `.gitignore` to allow tracking of `.template` files.
- **VPN Connectivity & Routing**
  - Fixed "Read-only file system" error by simplifying `AllowedIPs` to `172.30.30.0/24`.
  - Resolved `resolvconf` issues by removing DNS entries from client configs.
  - Enforced Static IPs and improved NAT routing detection.
  - Corrected UDP2RAW parameter to `--raw-mode faketcp`.
  - Resolved port conflicts by moving obfuscation WG listeners to `51821`.
- **Reliability & Logging**
  - Fixed empty Suricata logs by disabling checksum validation.
  - Improved log rotation and added a fail-fast mechanism to scripts.

## 2026-02-01
### Fixed
- **Configuration & Secrets**
    - Corrected WireGuard client configurations (`wg0.conf`) with keys matching the server.
    - Updated `.gitignore` to track `wg0.conf` files for easier lab setup.
    - Updated `README.md` to remove manual template copying steps and add `tcpdump` requirement.
- **UDP2RAW Build**
    - Added missing `Dockerfile` for `services/udp2raw` to build from source (using `wget` instead of `git` to avoid auth issues).
    - Corrected build URL to `wangyu-/udp2raw` (tag `20230206.0`).
    - Updated `compose.udp2raw.yml` to use local build context.
- **Experiment Execution**
    - Fixed missing PCAP files by installing `tcpdump` on the host system.
    - Verified all scenarios (Baseline, UDP2RAW, OBFS4) run successfully.

### Added
- **Network Security Monitoring (Zeek)**
    - Integrated Zeek IDS container (`network_mode: host`) to capture flow logs (`conn.log`, `dns.log`, etc.).
    - Configured automatic log collection into `results/runs/<timestamp>/zeek/`.
- **Enhanced Result Structure**
    - Refactored experiment results to use subdirectories: `pcap/`, `suricata/`, `zeek/`.
    - Changed timestamp format to `DD-MM-YYYY-HH-MM-SS` for better readability.
    - Updated `README.md` with Analysis Guide and Author Information.
- **Traffic Generation Modes**
    - Implemented `TRAFFIC_MODE` support (Burst vs Streaming).
    - Integrated `iperf3` for generating long-duration TCP flows (essential for flow analysis).
    - Added visual progress bar for real-time feedback during experiments.
- **Analysis Environment**
    - Debugged and enhanced `Analysis_Starter.ipynb` (Fixed Zeek log parsing for empty/short streams).
    - **Fixed Suricata Parser:** Correctly extracts `dest_port` and `proto` from EVE JSON logs (often located in root object).
    - **Improved Visualization:** Switched Packet IAT (Inter-Arrival Time) plots to Logarithmic Scale for better visibility of high-speed `iperf3` characteristics.
    - Added Entropy and Advanced DPI metrics.
