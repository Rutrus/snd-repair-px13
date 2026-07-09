#!/usr/bin/env bash
# Collect one resume window → validation/phase5-resume-timeline.csv
# Usage: ./scripts/phase5-resume-collect.sh [--notes "N"] [--force] [--with-matrix]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${REPO}/validation/phase5-resume-timeline.csv"
TEMPLATE="${REPO}/research/phase-5/templates/resume-timeline.csv"
MATRIX="${REPO}/validation/fw-matrix.csv"
STATE_DIR="${REPO}/validation/.state"

if [[ ! -f "$OUT" ]]; then
	cp "$TEMPLATE" "$OUT"
fi

NOTES=""
FORCE=0
WITH_MATRIX=0
while [[ $# -gt 0 ]]; do
	case "$1" in
	--notes) NOTES="${2:-}"; shift 2 ;;
	--force) FORCE=1; shift ;;
	--with-matrix) WITH_MATRIX=1; shift ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

# Avoid journalctl | grep -q under pipefail (SIGPIPE → false "no suspend exit").
kmsg_has() {
	journalctl -k -b 0 --no-pager -g "$1" -q >/dev/null 2>&1
}

kmsg_lines() {
	journalctl -k -b 0 --no-pager -g "$1" 2>/dev/null || true
}

if ! journalctl -k -b 0 --no-pager >/dev/null 2>&1; then
	echo "Cannot read journalctl -k -b 0 (permissions? systemd-journal group?)" >&2
	exit 1
fi

if ! kmsg_has 'PM: suspend exit'; then
	echo "No PM suspend exit this boot — suspend/resume first, then collect." >&2
	exit 1
fi

PROC_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
STAMP="${STATE_DIR}/phase5-resume-${PROC_BOOT_ID}"
LATEST_RESUME="$(kmsg_lines 'PM: suspend exit' | tail -1 | awk '{print $1,$2,$3}')"

if [[ "$FORCE" -eq 0 && -f "$STAMP" ]]; then
	LAST_COLLECTED="$(cat "$STAMP" 2>/dev/null || true)"
	if [[ -n "$LATEST_RESUME" && "$LAST_COLLECTED" == "$LATEST_RESUME" ]]; then
		echo "Resume already collected for ${LATEST_RESUME} (boot ${PROC_BOOT_ID})." >&2
		echo "  New suspend → ./scripts/phase5-resume-collect.sh --force --notes \"…\" [--with-matrix]" >&2
		exit 0
	fi
fi

RESUME_LINE="$(kmsg_lines 'PM: suspend exit' | tail -1)"
RESUME_TS="$(echo "$RESUME_LINE" | awk '{print $1,$2,$3}')"
RESUME_ISO="$(date -d "$RESUME_TS" -Is 2>/dev/null | cut -d+ -f1)"
RESUME_EPOCH="$(date -d "$RESUME_TS" +%s 2>/dev/null || date +%s)"

SUSPEND_LINE="$(kmsg_lines 'PM: suspend entry' | tail -1)"
SUSPEND_TS="$(echo "$SUSPEND_LINE" | awk '{print $1,$2,$3}')"

next_matrix_id() {
	if [[ ! -f "$MATRIX" ]]; then
		echo 1
		return
	fi
	local n
	n="$(awk -F, 'NR>1 {print $1}' "$MATRIX" | sort -n | tail -1)"
	echo $((n + 1))
}

BOOT_ID="$(next_matrix_id)"

append_row() {
	local off_ms="$1" layer="$2" event="$3"
	local u8d="${4:-}" u8o="${5:-}"
	echo "${BOOT_ID},${RESUME_ISO},${off_ms},${layer},${event},${u8d},${u8o},,,${NOTES}" >>"$OUT"
}

off_ms_from_ts() {
	local ts="$1"
	local epoch
	epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
	echo $(( (epoch - RESUME_EPOCH) * 1000 ))
}

if [[ -n "$SUSPEND_TS" && "$SUSPEND_TS" != "  " ]]; then
	append_row "$(off_ms_from_ts "$SUSPEND_TS")" PM "suspend entry (s2idle)"
fi
append_row 0 PM "suspend exit"

while IFS= read -r line; do
	ts="$(echo "$line" | awk '{print $1,$2,$3}')"
	off="$(off_ms_from_ts "$ts")"
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* //')"
	if echo "$body" | grep -q ':8:'; then
		append_row "$off" kernel "PM failed to resume -110 :8"
	elif echo "$body" | grep -q ':b:'; then
		append_row "$off" kernel "PM failed to resume -110 :b"
	elif echo "$body" | grep -q 'rt721'; then
		append_row "$off" kernel "PM failed to resume -110 rt721"
	fi
done < <(journalctl -k -b 0 --no-pager --since "$RESUME_TS" -g 'failed to resume' 2>/dev/null || true)

while IFS= read -r line; do
	ts="$(echo "$line" | awk '{print $1,$2,$3}')"
	off="$(off_ms_from_ts "$ts")"
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* //')"
	if echo "$body" | grep -q 'px13-audio-fix:'; then
		short="$(echo "$body" | sed 's/.*px13-audio-fix: //')"
		append_row "$off" px13 "$short"
	elif echo "$body" | grep -q 'playback without fw'; then
		append_row "$off" kernel ":8 playback without fw done=0" 0 0
		break
	elif echo "$body" | grep -q 'fw download wait timeout'; then
		append_row "$off" kernel ":8 fw download wait timeout in hw_params" 0 0
		break
	elif echo "$body" | grep -q 'hw_params ENTER uid=0x8'; then
		append_row "$off" kernel "first hw_params ENTER :8"
		break
	fi
done < <(journalctl -b 0 --no-pager --since "$RESUME_TS" 2>/dev/null \
	| grep -iE 'px13-audio-fix:|playback without fw|fw download wait timeout|hw_params ENTER uid=0x8' || true)

if [[ "$WITH_MATRIX" -eq 1 ]]; then
	"$REPO/scripts/fw-validation-collect.sh" --suspend --force --notes "phase5-${NOTES:-collect}" 2>/dev/null || true
fi

mkdir -p "$STATE_DIR"
echo "$RESUME_TS" >"$STAMP"

echo "Appended timeline → $OUT (boot_id=${BOOT_ID}, resume=${RESUME_ISO})"
echo "Run: ./scripts/phase5-check-invariants.sh"
