#!/usr/bin/env bash
# S140 — ACP SoundWire manager platform rebind only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="S140"
salvage_log "step ${SID}: manager rebind"
stop_pipewire_all
drop_alsa_users
bf_kernel_objects_snapshot "S140-before"
salvage_manager_rebind || true
sleep "${BF_FW_SETTLE_SEC}"
bf_kernel_objects_snapshot "S140-after"
start_pipewire_all
bf_strategy_finish "$SID"
