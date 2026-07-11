#!/usr/bin/env bash
# S002 — PipeWire restart permutations + alsactl + udev.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S002"
bf_log "strategy ${SID}: pipewire permutations + alsactl + udev"
stop_pipewire_all
sleep 1
bf_alsactl_restore
bf_udev_trigger
bf_restart_pipewire_users
sleep "${BF_SETTLE_SEC}"
bf_test_alsa && bf_report_pass "$SID" || bf_report_fail "$SID"
