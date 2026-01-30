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
- **Project structure**
  - Separated baseline/obfuscation configs into distinct compose files
  - Improved services/ directory organization (gateway/udp2raw, wg-client/obfs4, etc.)
  - Run scripts now explicitly use `-f compose.yml -f compose.<scenario>.yml`

### Technical Details
- All scenarios use identical `client-node` for consistent application traffic
- WireGuard client configs point to localhost:51820 for obfuscation scenarios
  - UDP2RAW and OBFS4 unwrap at localhost:51820 before WireGuard client connects
- Suricata captures on correct port per scenario (UDP/51820, TCP/443, TCP/12345)
- tcpdump runs parallel to Suricata for independent packet capture
- All experiment artifacts timestamped and organized per scenario
- Environment variables from `.env` are automatically loaded by `docker compose`
  - Scripts use `-f compose.yml -f compose.<scenario>.yml` without explicit sourcing

### Fixed
- Removed circular dependency in compose.udp2raw.yml and compose.obfs4.yml
  - `udp2raw-client` and `obfs4-client` now share network namespace without depends_on loops
