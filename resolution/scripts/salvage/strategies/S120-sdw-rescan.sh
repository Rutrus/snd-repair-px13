#!/usr/bin/env bash
# S120 — SoundWire bus rescan only (master/slave re-enumeration).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="S120"
salvage_log "step ${SID}: SoundWire bus rescan"
stop_pipewire_all
drop_alsa_users
bf_kernel_objects_snapshot "S120-before"
salvage_sdw_bus_rescan || true
sleep "${BF_FW_SETTLE_SEC}"
bf_kernel_objects_snapshot "S120-after"
start_pipewire_all
bf_strategy_finish "$SID"
