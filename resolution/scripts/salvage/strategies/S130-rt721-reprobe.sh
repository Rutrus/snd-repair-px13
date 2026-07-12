#!/usr/bin/env bash
# S130 — RT721 codec reprobe only (ACP untouched).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="S130"
salvage_log "step ${SID}: RT721 reprobe"
stop_pipewire_all
drop_alsa_users
bf_kernel_objects_snapshot "S130-before"
salvage_rt721_reprobe || true
sleep "${BF_FW_SETTLE_SEC}"
bf_kernel_objects_snapshot "S130-after"
start_pipewire_all
bf_strategy_finish "$SID"
