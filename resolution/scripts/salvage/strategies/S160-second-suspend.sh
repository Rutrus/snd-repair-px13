#!/usr/bin/env bash
# S160 — Second suspend cycle (bug sometimes clears on 2nd S2).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="S160"
salvage_log "step ${SID}: secondary suspend"
export RESOLUTION_ASSUME_SUSPEND=1
systemctl suspend || {
	salvage_action_skip "second_suspend" "systemctl suspend failed"
	bf_report_fail "$SID"
	exit 1
}
salvage_action_ok "second_suspend"
wait_post_resume_settle
start_pipewire_all
bf_strategy_finish "$SID"
