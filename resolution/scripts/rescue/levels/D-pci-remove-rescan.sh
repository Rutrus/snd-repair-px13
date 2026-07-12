#!/usr/bin/env bash
# D — PCI remove + rescan (aggressive enumeration reset).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="D"
rescue_log "level ${LID}: PCI remove+rescan"
stop_pipewire_all
drop_alsa_users
salvage_full_stack_destroy || true
if pci_remove_rescan; then
	salvage_action_ok "pci_remove_rescan"
else
	salvage_action_skip "pci_remove_rescan" "failed"
fi
sleep "${BF_FW_SETTLE_SEC}"
pci_reset_acp || true
rescue_rebuild_standard
start_pipewire_all
rescue_finish "$LID"
