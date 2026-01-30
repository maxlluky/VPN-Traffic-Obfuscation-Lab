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
  - `compose.yml` (Base), `compose.baseline.yml` (WireGuard), `compose.udp2raw.yml` (TCP/443 wrapping), `compose.obfs4.yml` (OBFS4 wrapping).
- **UDP2RAW & OBFS4 Scenarios**
  - Implemented full service stacks for both obfuscation methods with client/server proxies.
  - Added dedicated entrypoint scripts with dynamic hostname resolution.
  - Automated experiment runners (`run_udp2raw.sh`, `run_obfs4.sh`).
- **Enhanced Configuration & Documentation**
  - Expanded `.env` with image tags and obfuscation ports.
  - Rewrote README.md with detailed topology diagrams and usage instructions.

### Changed
- **Traffic Sniffing Strategy**: Switched sniffing interface to `client_net` to capture traffic *before* NAT/Gateway processing, ensuring visibility of the actual WireGuard/Obfuscated packets.
- **Project Structure**: Organized services into logical subdirectories (`gateway/udp2raw`, `wg-client/obfs4`, etc.).

### Fixed
- **Stability & Cleanup**: Implemented robust `down --remove-orphans` logic in all scripts to prevent IP/Port conflicts when switching scenarios.
- **UDP2RAW Implementation**:
  - Fixed missing runtime dependencies (`libstdc++`) in Alpine image.
  - Resolved `ListenPort` conflicts between WireGuard and local proxies.
  - Added `faketcp` mode support.
- **Traffic Analysis**:
  - Corrected Suricata rules to detect specific obfuscation ports (TCP 443/12345) and UDP 51820.
  - Fixed empty PCAP issues by sniffing the correct bridge interface.
  - Added timeouts to traffic generators to prevent hangs during connection failures.
