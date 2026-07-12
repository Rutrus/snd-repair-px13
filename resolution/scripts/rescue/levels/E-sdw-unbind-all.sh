#!/usr/bin/env bash
# E — Unbind ALL SoundWire devices + drivers_probe.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="E"
rescue_log "level ${LID}: unbind all SoundWire + reprobe"
stop_pipewire_all
drop_alsa_users
salvage_sdw_unbind_all || salvage_action_skip "sdw_unbind" "none bound"
sleep 2
salvage_sdw_bus_rescan || true
sleep "${BF_FW_SETTLE_SEC}"
salvage_rt721_reprobe || true
start_pipewire_all
rescue_finish "$LID"
