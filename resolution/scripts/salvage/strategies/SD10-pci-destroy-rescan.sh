#!/usr/bin/env bash
# SD10 — Destroy PCI function: remove + rescan (verify device gone, then back).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="SD10"
salvage_log "step ${SID}: PCI remove+rescan (full enumeration)"
stop_pipewire_all
drop_alsa_users
bf_kernel_objects_snapshot "SD10-before"
salvage_level_report "before"

if ! pci_remove_rescan; then
	salvage_action_skip "pci_remove_rescan" "failed"
	bf_report_fail "$SID"
	exit 1
fi
salvage_action_ok "pci_remove_rescan"

sleep "${BF_FW_SETTLE_SEC}"
if [[ -d "$(pci_sysfs)" ]] && salvage_pci_driver_bound; then
	salvage_log "PCI device returned and driver bound"
else
	salvage_log "WARN: PCI device or driver not fully back yet"
fi
salvage_level_report "after_pci"

bf_load_audio_modules
start_pipewire_all
bf_kernel_objects_snapshot "SD10-after"
bf_strategy_finish "$SID"
