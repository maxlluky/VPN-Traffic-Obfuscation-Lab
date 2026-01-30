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
  - Refactored monolithic `compose.yml` into modular base + scenario overrides
  - `compose.yml` – Base configuration (target, suricata, shared networks)
  - `compose.baseline.yml` – Plain WireGuard scenario
  - `compose.udp2raw.yml` – UDP2RAW obfuscation (TCP/443 wrapping)
  - `compose.obfs4.yml` – OBFS4 obfuscation (obfs4 protocol wrapping)

- **UDP2RAW obfuscation scenario**
  - `services/gateway/udp2raw/` – Server-side UDP2RAW tunnel (unwraps TCP→UDP)
  - `services/wg-client/udp2raw/` – Client-side UDP2RAW tunnel (wraps UDP→TCP)
  - WireGuard traffic wrapped in TCP/443 for stealth
  - `scripts/runs/run_udp2raw.sh` – Automated experiment runner

- **OBFS4 obfuscation scenario**
  - `services/obfs4/` – OBFS4 proxy build context (Dockerfile + entrypoints)
  - `services/wg-client/obfs4/` – Client-side obfs4 configuration
  - WireGuard traffic wrapped in obfs4 protocol
  - Builds obfs4proxy from source (Yawning/obfs4)
  - `scripts/runs/run_obfs4.sh` – Automated experiment runner

- **Enhanced .env configuration**
  - Added `UDP2RAW_IMAGE`, `OBFS4_IMAGE` for container images
  - Added `UDP2RAW_GATEWAY_PORT` (default: 443) for TCP stealth
  - Added `OBFS4_PORT` (default: 12345) for obfs4 listener
  - Organized .env with sections for clarity

- **Comprehensive documentation**
  - Rewrote README.md with complete scenario descriptions
  - Added traffic flow diagrams for all three scenarios
  - Architecture explanation for modular compose setup
  - Troubleshooting guide with scenario-specific issues
  - Advanced usage examples with custom parameters

### Changed
- **Project Structure Refactor**
  - Moved all Docker Compose files (`compose*.yml`) and configuration (`.env`, `.env.example`) into a dedicated `compose/` directory.
  - Updated all automation scripts (`run_*.sh`) to support the new directory structure.
  - Improved `services/` directory organization (gateway/udp2raw, wg-client/obfs4, etc.).
  - Run scripts now explicitly use `--env-file` and `-f` flags to locate config files correctly.

### Fixed
- **Reliability & Logging**
  - Resolved issue with empty Suricata logs (`fast.log`) by disabling checksum validation (`stream.checksum-validation: no`) for virtualized environments.
  - Fixed log rotation logic: truncated logs *before* starting Suricata to prevent sparse file issues.
  - Implemented **fail-fast mechanism** in all run scripts: experiments abort immediately after 10 consecutive connection timeouts.

- **Networking & Stability**
  - **Enforced Static IPs**: Replaced all hostname references with static IPs in `compose.*.yml` and entrypoints to remove DNS dependency and race conditions.
  - **NAT Routing**: Improved gateway `10-nat.sh` to auto-detect the correct WAN interface instead of assuming `eth1`.
  - **UDP2RAW**: Corrected invalid parameter `--raw-mode TCP` to `--raw-mode faketcp`.
  - **Port Conflicts**: Changed WireGuard listen port to `51821` in obfuscation clients to avoid conflict with local tunnel endpoints on `51820`.
