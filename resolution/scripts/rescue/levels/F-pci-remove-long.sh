#!/usr/bin/env bash
# F — PCI remove + long settle + udev + full modprobe (ugly but thorough).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="F"
rescue_log "level ${LID}: PCI remove long settle + full reload"
stop_pipewire_all
drop_alsa_users
salvage_full_stack_destroy || true
salvage_pci_remove_long
pci_reset_acp || true
rescue_rebuild_standard
start_pipewire_all
sleep "${BF_FW_SETTLE_SEC}"
rescue_finish "$LID"
