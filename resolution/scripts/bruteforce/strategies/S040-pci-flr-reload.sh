#!/usr/bin/env bash
# S040 — PCI FLR / reprobe (while bound) + module reload.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S040"
bf_log "strategy ${SID}: PCI FLR + module reload"
stop_pipewire_all
sleep 1
if bf_pci_flr_reset; then
	bf_log "FLR issued"
	sleep 3
else
	bf_log "FLR not available — pci_reset before unload"
	pci_reset_acp || bf_log "pci_reset failed"
	sleep 2
fi
bf_unload_audio_modules
sleep 1
bf_load_audio_modules
sleep "${BF_FW_SETTLE_SEC}"
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_strategy_finish "$SID"
