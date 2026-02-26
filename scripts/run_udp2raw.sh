#!/usr/bin/env bash
# Thin wrapper for backward compatibility.
# Delegates to the unified run_scenario.sh.
exec "$(dirname "${BASH_SOURCE[0]}")/run_scenario.sh" udp2raw "$@"
