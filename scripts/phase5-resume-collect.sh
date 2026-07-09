#!/usr/bin/env bash
# Collect one resume window → validation/phase5-resume-timeline.csv
# Usage: ./scripts/phase5-resume-collect.sh [--notes "N"]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${REPO}/validation/phase5-resume-timeline.csv"
TEMPLATE="${REPO}/research/phase-5/templates/resume-timeline.csv"

if [[ ! -f "$OUT" ]]; then
	cp "$TEMPLATE" "$OUT"
fi

NOTES=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--notes) NOTES="${2:-}"; shift 2 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

if ! journalctl -k -b 0 --no-pager 2>/dev/null | grep -q 'PM: suspend exit'; then
	echo "No PM suspend exit this boot — run after resume" >&2
	exit 1
fi

BOOT_ID="$(wc -l < "$OUT" | tr -d ' ')"
RESUME_TS="$(journalctl -k -b 0 --no-pager 2>/dev/null \
	| grep 'PM: suspend exit' | tail -1 | awk '{print $1,$2,$3}')"
RESUME_EPOCH="$(date -d "$RESUME_TS" +%s 2>/dev/null || date +%s)"

append_row() {
	local off_ms="$1" layer="$2" event="$3"
	echo "${BOOT_ID},${RESUME_TS},${off_ms},${layer},${event},,,,${NOTES}" >>"$OUT"
}

append_row 0 PM "suspend exit"

while IFS= read -r line; do
	ts="$(echo "$line" | awk '{print $1,$2,$3}')"
	epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
	off=$(( (epoch - RESUME_EPOCH) * 1000 ))
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* //')"
	if echo "$body" | grep -qE 'failed to resume|playback without fw|px13-audio-fix'; then
		append_row "$off" kernel "$body"
	fi
done < <(journalctl -b 0 --no-pager 2>/dev/null \
	| grep -iE 'failed to resume|playback without fw|px13-audio-fix' || true)

"$REPO/scripts/fw-validation-collect.sh" --suspend --force --notes "phase5-${NOTES:-collect}" 2>/dev/null || true

echo "Appended timeline hints → $OUT"
echo "Run: ./scripts/phase5-check-invariants.sh"
