#!/usr/bin/env bash
# S070 — PCI remove + rescan (full re-enumeration) + module reload.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S070"
bf_log "strategy ${SID}: PCI remove+rescan (distinct from unbind)"
bf_kernel_objects_snapshot "S070-before"
stop_pipewire_all
drop_alsa_users
bf_unload_audio_modules
sleep 2
if pci_remove_rescan; then
	bf_log "pci_remove_rescan OK"
else
	bf_log "pci_remove_rescan failed"
	bf_report_fail "$SID"
	exit 1
fi
sleep "${BF_FW_SETTLE_SEC}"
# Kernel may auto-bind snd_pci_ps — force reprobe for full driver re-init
pci_reset_acp && bf_log "post-rescan pci_reset OK" || bf_log "post-rescan pci_reset skipped"
sleep "${BF_FW_SETTLE_SEC}"
bf_load_audio_modules
bf_alsactl_restore
bf_udev_trigger
start_pipewire_all
bf_kernel_objects_snapshot "S070-after"
bf_strategy_finish "$SID"
