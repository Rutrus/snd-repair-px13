#!/usr/bin/env bash
# S001 — Restart PipeWire + Wireplumber (all logged-in users).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S001"
bf_log "strategy ${SID}: user session audio restart"
stop_pipewire_all
sleep 2
start_pipewire_all
sleep "${BF_SETTLE_SEC}"
bf_test_alsa && bf_report_pass "$SID" || bf_report_fail "$SID"
