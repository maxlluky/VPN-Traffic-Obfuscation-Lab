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
