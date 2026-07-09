#!/usr/bin/env bash
# N× suspend/resume statistics for phase 5 (T09). Manual recovery on failure.
#
# Usage:
#   ./scripts/phase5-resume-stats-loop.sh --count 10 --wait 90
#   PHASE5_DRY_RUN=1 ./scripts/phase5-resume-stats-loop.sh --count 3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${REPO}/validation/phase5-resume-stats.csv"
COUNT=10
WAIT=90
DRY="${PHASE5_DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--count) COUNT="$2"; shift 2 ;;
	--wait)  WAIT="$2"; shift 2 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

if [[ ! -f "$OUT" ]]; then
	echo "run,timestamp,pm110,uid8_fw,uidb_fw,dummy_sink,load1,notes" >"$OUT"
fi

for ((i = 1; i <= COUNT; i++)); do
	echo "==> phase5 loop ${i}/${COUNT}"
	if [[ "$DRY" == "1" ]]; then
		echo "DRY_RUN: would systemctl suspend"
		sleep 2
		continue
	fi
	systemctl suspend || { echo "suspend failed"; exit 1; }
	sleep "$WAIT"
	PM110="$(journalctl -k -b 0 --no-pager -S "-2 min" 2>/dev/null \
		| grep -c 'failed to resume: error -110' || true)"
	DUMMY="$(XDG_RUNTIME_DIR="/run/user/$(id -u)" wpctl status 2>/dev/null \
		| grep -c 'Dummy Output' || echo "?")"
	LOAD="$(awk '{print $1}' /proc/loadavg)"
	TS="$(date -Is)"
	"$REPO/scripts/fw-validation-collect.sh" --suspend --force --notes "phase5-loop-${i}" 2>/dev/null || true
	LAST="$(tail -1 "$REPO/validation/fw-matrix.csv")"
	UID8="$(echo "$LAST" | cut -d, -f4)"
	UIDB="$(echo "$LAST" | cut -d, -f5)"
	echo "${i},${TS},${PM110},${UID8},${UIDB},${DUMMY},${LOAD},loop" >>"$OUT"
	if [[ "$UID8" == "WARN" ]]; then
		echo "WARN: :8 failed — stop loop with Ctrl+C or continue; reboot may be needed"
	fi
done

echo "Stats → $OUT"
