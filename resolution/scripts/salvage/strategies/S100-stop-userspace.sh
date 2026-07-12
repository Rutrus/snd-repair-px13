#!/usr/bin/env bash
# S100 — Stop userspace audio (WirePlumber/PipeWire).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="S100"
salvage_log "step ${SID}: stop userspace"
salvage_stop_userspace
sleep 2
bf_strategy_finish "$SID"
