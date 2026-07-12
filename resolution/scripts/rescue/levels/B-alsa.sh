#!/usr/bin/env bash
# B — ALSA restore + udev + drop PCM holders.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="B"
rescue_log "level ${LID}: ALSA restore + udev"
salvage_drop_pcm_nodes
bf_alsactl_restore
bf_udev_trigger
sleep "${BF_SETTLE_SEC}"
start_pipewire_all
rescue_finish "$LID"
