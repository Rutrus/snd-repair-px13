#!/usr/bin/env bash
# SD20 — Destroy SoundWire: SOF down first, then soundwire modules, verify gone.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="SD20"
salvage_log "step ${SID}: destroy SoundWire stack (SOF first)"
stop_pipewire_all
drop_alsa_users
bf_kernel_objects_snapshot "SD20-before"
salvage_level_report "before"

# Must clear snd_pci_ps before SOF/soundwire on PX13
salvage_rmmod_modules snd_pci_ps snd_acp_sdw_legacy_mach snd_soc_rt721_sdca 2>/dev/null || true
salvage_rmmod_modules snd_sof_amd_acp snd_sof_pci snd_sof 2>/dev/null || true
salvage_rmmod_modules soundwire_amd snd_amd_sdw_acpi soundwire_bus 2>/dev/null || true
sleep 2

if salvage_soundwire_stack_present; then
	salvage_action_skip "soundwire_destroy" "modules still loaded"
	salvage_module_holders_report
else
	salvage_action_ok "soundwire_destroy" "stack gone"
fi
salvage_level_report "after_destroy"

salvage_rebuild_bottomup
start_pipewire_all
bf_kernel_objects_snapshot "SD20-after"
bf_strategy_finish "$SID"
