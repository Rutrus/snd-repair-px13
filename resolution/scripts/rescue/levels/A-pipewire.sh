#!/usr/bin/env bash
# A — Restart PipeWire / WirePlumber.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="A"
rescue_log "level ${LID}: restart userspace audio"
stop_pipewire_all
sleep +2
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
rescue_finish "$LID"
