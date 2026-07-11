#!/usr/bin/env bash
# S010 — Full SoundWire/ACP module reload (R06 extended).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S010"
bf_log "strategy ${SID}: unload/load audio module stack"
stop_pipewire_all
sleep 1
bf_unload_audio_modules
sleep 2
bf_load_audio_modules
sleep "${BF_FW_SETTLE_SEC}"
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_test_alsa && bf_report_pass "$SID" || bf_report_fail "$SID"
