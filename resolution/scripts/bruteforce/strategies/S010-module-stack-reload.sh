#!/usr/bin/env bash
# S010 — Full SoundWire/ACP module reload (R200).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S010"
bf_log "strategy ${SID}: unload/load audio module stack"
bf_kernel_objects_snapshot "S010-before"
stop_pipewire_all
sleep 1
bf_unload_audio_modules
sleep 2
bf_kernel_objects_snapshot "S010-after-unload"
bf_load_audio_modules
sleep "${BF_FW_SETTLE_SEC}"
bf_kernel_objects_snapshot "S010-after-load"
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_strategy_finish "$SID"
