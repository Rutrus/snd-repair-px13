#!/usr/bin/env bash
# S030 — Unload modules → runtime PM cycle → reload (no PCI unbind).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S030"
bf_log "strategy ${SID}: modules down → runtime PM → modules up"
stop_pipewire_all
sleep 1
bf_unload_audio_modules
sleep 2
bf_runtime_pm_cycle || bf_log "runtime PM cycle incomplete"
sleep 2
bf_load_audio_modules
sleep "${BF_FW_SETTLE_SEC}"
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_strategy_finish "$SID"
