#!/usr/bin/env bash
# C — Destroy FULL stack (SOF → SoundWire → snd_pci_ps) then rebuild from zero.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="C"
rescue_log "level ${LID}: full stack destroy + probe from zero"
salvage_level_report "C-before"
salvage_full_stack_destroy || rescue_log "WARN: partial destroy — continuing rebuild anyway"
rescue_rebuild_standard
start_pipewire_all
salvage_level_report "C-after"
rescue_finish "$LID"
