#!/usr/bin/env bash
# S050 — ACPI D3→D0 on PCI device + module reload.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S050"
bf_log "strategy ${SID}: ACPI D3/D0 + module reload"
stop_pipewire_all
sleep 1
bf_unload_audio_modules
sleep 1
bf_acpi_d3_d0 || bf_log "ACPI cycle partial"
sleep 2
bf_load_audio_modules
sleep "${BF_FW_SETTLE_SEC}"
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_strategy_finish "$SID"
