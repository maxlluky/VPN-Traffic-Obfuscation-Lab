# Lab Notes

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
