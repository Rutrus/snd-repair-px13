#!/usr/bin/env bash
# S040 — PCI FLR reset (if supported) + module reload.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S040"
PCI_SYS="$(pci_sysfs)"
bf_log "strategy ${SID}: PCI FLR + module reload"
stop_pipewire_all
sleep 1
bf_unload_audio_modules
sleep 1
if bf_pci_flr_reset; then
	sleep 3
else
	bf_log "FLR not available — fallback pci_reset"
	pci_reset_acp || true
	sleep 2
fi
bf_load_audio_modules
sleep "${BF_FW_SETTLE_SEC}"
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_test_alsa && bf_report_pass "$SID" || bf_report_fail "$SID"
