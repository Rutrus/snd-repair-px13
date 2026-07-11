#!/usr/bin/env bash
# R01 — Layer 0: restart PipeWire + WirePlumber only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

log "R01: restart PipeWire (L0)"
stop_pipewire_all
sleep 2
start_pipewire_all
sleep 2
witness_audio
log "R01 done — record PASS/FAIL in resolution/TRACKER.md"
