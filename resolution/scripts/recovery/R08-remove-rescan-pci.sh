#!/usr/bin/env bash
# R08 — Layer 4: PCI remove + rescan (full re-enumeration).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

dev="$(pci_sysfs)"
[[ -e "$dev/remove" ]] || {
	log "R08: $dev/remove missing"
	exit 1
}

log "R08: PCI remove+rescan $PCI_DEV (L4, HIGH RISK)"
log "have reboot ready if device does not return"

echo 1 > "$dev/remove"
sleep 2
echo 1 > /sys/bus/pci/rescan
sleep 5

for _ in $(seq 1 60); do
	grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && break
	sleep 0.5
done

start_pipewire_all
witness_audio
log "R08 done — record PASS/FAIL in resolution/TRACKER.md"
