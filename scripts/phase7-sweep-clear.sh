#!/usr/bin/env bash
# Remove Phase 7 modprobe.d drop-in after sweep completes.
set -euo pipefail
MODPROBE_D="/etc/modprobe.d/snd-repair-phase7.conf"
if [[ -f "$MODPROBE_D" ]]; then
	sudo rm -f "$MODPROBE_D"
	echo "Removed ${MODPROBE_D}"
else
	echo "No ${MODPROBE_D} (already clean)"
fi
echo "Reboot to load soundwire_amd with default phase7_delay_ms=0"
