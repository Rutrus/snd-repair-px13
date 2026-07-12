#!/usr/bin/env bash
# S150 — PCI remove + rescan (distinct from unbind/bind).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="S150"
salvage_log "step ${SID}: PCI remove+rescan"
stop_pipewire_all
drop_alsa_users
bf_kernel_objects_snapshot "S150-before"
if pci_remove_rescan; then
	salvage_action_ok "pci_remove_rescan"
else
	salvage_action_skip "pci_remove_rescan" "failed"
fi
sleep "${BF_FW_SETTLE_SEC}"
pci_reset_acp || true
sleep "${BF_FW_SETTLE_SEC}"
bf_load_audio_modules
start_pipewire_all
bf_kernel_objects_snapshot "S150-after"
bf_strategy_finish "$SID"
