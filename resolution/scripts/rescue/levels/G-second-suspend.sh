#!/usr/bin/env bash
# G — Second suspend cycle (bug sometimes clears on 2nd S2).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="G"
rescue_log "level ${LID}: secondary suspend"
export RESOLUTION_ASSUME_SUSPEND=1
systemctl suspend || {
	rescue_log "suspend failed"
	bf_report_fail "$LID"
	exit 1
}
wait_post_resume_settle
start_pipewire_all
rescue_finish "$LID"
