#!/usr/bin/env bash
# Restore boot audio after accidental anchor unload (audit bug / manual rmmod).
# Usage: sudo restore-boot-audio.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_root "$0"
salvage_log "restore boot audio — $(bf_timestamp)"

if alsa_card_present && witness_playback_alsa_hw_primary; then
	salvage_log "S0 already OK — nothing to do"
	exit 0
fi

stop_pipewire_all
sleep 1
drop_alsa_users

if ! bf_module_loaded "$BF_ANCHOR_MOD"; then
	salvage_log "loading ${BF_ANCHOR_MOD}"
	modprobe -va "$BF_ANCHOR_MOD" 2>&1 | sed 's/^/[salvage]   /' || true
fi

if ! pci_driver_dir &>/dev/null; then
	if [[ -d "/sys/bus/pci/drivers/snd_pci_ps" ]]; then
		salvage_log "binding PCI device to snd_pci_ps"
		pci_write "$PCI_DEV" "/sys/bus/pci/drivers/snd_pci_ps/bind" || true
	fi
fi

if ! alsa_card_present && [[ -w "$(pci_sysfs)/remove" ]]; then
	salvage_log "card still missing — PCI remove+rescan"
	pci_remove_rescan || true
	sleep "${BF_FW_SETTLE_SEC}"
	modprobe -va "$BF_ANCHOR_MOD" 2>/dev/null || true
fi

salvage_log "FW settle ${BF_FW_SETTLE_SEC}s"
sleep "${BF_FW_SETTLE_SEC}"
command -v alsactl >/dev/null 2>&1 && alsactl restore 2>/dev/null || true
start_pipewire_all
sleep 2

if alsa_card_present; then
	salvage_log "card: $(grep amd-soundwire /proc/asound/cards || echo missing)"
else
	salvage_log "FAIL: card still missing — reboot recommended"
	exit 1
fi

if confirm_s0_health; then
	salvage_log "S0 OK — safe for s2-reproduce.sh"
	exit 0
fi

salvage_log "card present but playback failed — check plughw or reboot"
exit 2
