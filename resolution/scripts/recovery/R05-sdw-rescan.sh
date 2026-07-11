#!/usr/bin/env bash
# R05 — Layer 2: SoundWire bus rescan.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

if [[ -w /sys/bus/soundwire/rescan ]]; then
	log "R05: echo 1 > /sys/bus/soundwire/rescan"
	echo 1 > /sys/bus/soundwire/rescan
elif [[ -w /sys/bus/soundwire/drivers_probe ]]; then
	log "R05: echo soundwire > drivers_probe"
	echo soundwire > /sys/bus/soundwire/drivers_probe
else
	log "R05: no rescan sysfs — try R04 instead"
	exit 1
fi

sleep 3
start_pipewire_all
witness_audio
log "R05 done — record PASS/FAIL in resolution/TRACKER.md"
