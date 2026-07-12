#!/usr/bin/env bash
# S060 — Apply S020 then second system suspend (R10 pattern).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
SID="S060"
bf_log "strategy ${SID}: nuclear recovery + second suspend"
"${SCRIPT_DIR}/strategies/S020-nuclear-pci-modules.sh" || true
sleep 5
bf_log "secondary suspend"
systemctl suspend
wait_post_resume_settle
export RESOLUTION_ASSUME_SUSPEND=1
sleep "${BF_SETTLE_SEC}"
bf_strategy_finish "$SID"
