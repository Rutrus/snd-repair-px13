#!/usr/bin/env bash
# SD30 — Destroy SOF stack only (then rebuild).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="SD30"
salvage_log "step ${SID}: destroy SOF (snd_sof_amd_acp chain)"
stop_pipewire_all
drop_alsa_users
salvage_level_report "before"

salvage_rmmod_modules snd_pci_ps
salvage_rmmod_modules snd_sof_amd_acp63 snd_sof_amd_acp70 snd_sof_amd_rembrandt \
	snd_sof_amd_vangogh snd_sof_amd_renoir snd_sof_amd_acp snd_sof_pci snd_sof
sleep 2

if salvage_sof_stack_present; then
	salvage_action_skip "sof_destroy" "SOF still loaded"
	salvage_module_holders_report
else
	salvage_action_ok "sof_destroy" "SOF gone"
fi
salvage_level_report "after_sof"

bf_load_audio_modules
start_pipewire_all
bf_strategy_finish "$SID"
