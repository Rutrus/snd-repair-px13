#!/usr/bin/env bash
# S020 — Nuclear: stop → PCI reprobe (while driver loaded) → unload → reload → userspace.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S020"
bf_log "strategy ${SID}: PCI reprobe BEFORE unload, then full stack reload"
stop_pipewire_all
sleep 1
pci_reset_acp && bf_log "pci_reset OK" || bf_log "pci_reset failed (continuing)"
sleep 2
bf_unload_audio_modules
sleep 2
bf_load_audio_modules
sleep "${BF_FW_SETTLE_SEC}"
bf_alsactl_restore
bf_udev_trigger
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_strategy_finish "$SID"
