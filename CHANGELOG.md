# Changelog

## [Unreleased] - 2026-01-31

### Added
- **Obfs4 SIP003 Adapter (`pt_adapter.py`)**: Implemented a custom Python adapter to bridge `shadowsocks-rust` (SIP003 protocol) with `obfs4proxy` (Tor Pluggable Transport). This enables proper tunneling of UDP (WireGuard) traffic over the TCP-based Obfs4 transport.
- **Dockerfile Updates**: Added `python3` dependency for the adapter.

### Fixed
- **Obfs4 Traffic Flow**: Resolved issue where `obfs4proxy` rejected UDP traffic by encapsulating it first with `shadowsocks-rust` using the new adapter.
- **Traffic Capture**: Corrected `run_obfs4.sh` tcpdump filter from `tcp port 12345` to `port 12345` to correctly capture the UDP-based Shadowsocks-over-Obfs4 traffic.
- **Obfs4 Permissions**: Fixed `chmod` permission error in `entrypoint.sh` for the adapter script.

### Changed
- **Suricata Rules**: Updated `local.rules` to correctly identify Obfs4 traffic as `ip/udp` instead of `tcp`, matching the `ss-server -U` behavior.
