#!/usr/bin/env bash
# R03 — Layer 2: unbind RT721 SoundWire slave only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

slave="$(discover_rt721_dev)" || {
	log "R03: RT721 device not found under /sys/bus/soundwire/devices/"
	log "discovered: $(discover_sdw_devices | tr '\n' ' ')"
	exit 1
}

drv_link="/sys/bus/soundwire/devices/${slave}/driver"
[[ -e "$drv_link" ]] || {
	log "R03: ${slave} has no driver — nothing to unbind"
	exit 1
}

drv="$(readlink -f "$drv_link")"
log "R03: unbind ${slave} from $(basename "$drv")"
echo "$slave" > "${drv}/unbind"
sleep 2
start_pipewire_all
witness_audio
log "R03 done — record PASS/FAIL in resolution/TRACKER.md"
