#!/usr/bin/env bash
# I — Warm reboot (defeats purpose of no-reboot but documents exhaustion).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="I"
rescue_log "level ${LID}: warm reboot (requires RESCUE_ALLOW_REBOOT=1)"

if [[ "${RESCUE_ALLOW_REBOOT:-0}" != "1" ]]; then
	rescue_log "SKIP: set RESCUE_ALLOW_REBOOT=1 to enable"
	echo "RESULT=SKIP LEVEL=${LID} REASON=reboot_not_enabled"
	exit 0
fi

rescue_log "rebooting in 5s..."
sleep 5
systemctl reboot
