#!/usr/bin/env bash
# R04 — Layer 2: unbind + rebind SoundWire manager (boot replay step 1).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

mgr="$(discover_manager_dev)" || {
	log "R04: manager device not found"
	log "discovered: $(discover_sdw_devices | tr '\n' ' ')"
	exit 1
}

drv_dir="$(manager_driver_dir)" || {
	log "R04: SoundWire manager driver dir not found"
	exit 1
}

log "R04: rebind manager ${mgr} via $(basename "$drv_dir")"

if [[ -e "${drv_dir}/${mgr}" ]]; then
	echo "$mgr" > "${drv_dir}/unbind"
	sleep 2
fi

echo "$mgr" > "${drv_dir}/bind"
sleep 3

for _ in $(seq 1 40); do
	grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && break
	sleep 0.25
done

start_pipewire_all
witness_audio
log "R04 done — record PASS/FAIL in resolution/TRACKER.md"
