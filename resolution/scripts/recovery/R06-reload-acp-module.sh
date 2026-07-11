#!/usr/bin/env bash
# R06 — Layer 3: reload ACP / SoundWire kernel modules.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

# Order: dependents first on rmmod, reverse on modprobe
MODS_REMOVE=(snd_soc_amd_acp_mach snd_soc_amd_acp snd_soc_amd_sdw_utils snd_soc_amd_ps soundwire_amd soundwire_bus)
MODS_LOAD=(soundwire_bus soundwire_amd snd_soc_amd_ps snd_soc_amd_sdw_utils snd_soc_amd_acp snd_soc_amd_acp_mach)

log "R06: reload ACP/SoundWire modules (L3)"

for m in "${MODS_REMOVE[@]}"; do
	if lsmod | awk '{print $1}' | grep -qx "$m"; then
		log "  rmmod $m"
		modprobe -r "$m" 2>/dev/null || log "  rmmod $m failed (may need deps)"
	fi
done

sleep 2

for m in "${MODS_LOAD[@]}"; do
	log "  modprobe $m"
	modprobe "$m" 2>/dev/null || log "  modprobe $m failed"
done

sleep 3
start_pipewire_all
witness_audio
log "R06 done — record PASS/FAIL in resolution/TRACKER.md"
