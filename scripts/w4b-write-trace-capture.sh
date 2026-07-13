#!/usr/bin/env bash
# Capture W4b write trace from journal (optionally slice by time window).
#
# Usage:
#   sudo ./scripts/w4b-write-trace-capture.sh --label pass --window boot
#   sudo ./scripts/w4b-write-trace-capture.sh --label fail-s2 --window playback
#   sudo ./scripts/w4b-write-trace-capture.sh --label fail-s2 --window resume
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
LABEL=""
WINDOW="all"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="$2"; shift 2 ;;
	--window) WINDOW="$2"; shift 2 ;;
	-h|--help) sed -n '3,10p' "$0"; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date +%Y%m%d-%H%M%S)"
TAG="${LABEL:+$LABEL-}${TS}"
OUT="${REPO}/validation/w4b-write-${TAG}"
mkdir -p "$OUT"

{
	echo "time=$(date -Iseconds) label=${LABEL:-none} window=$WINDOW"
	echo "kernel=$(uname -r)"
	echo "suspend_count=$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -c 'PM: suspend entry' || true)"
} >"${OUT}/meta.txt"

journalctl -k -b 0 --no-pager 2>/dev/null | grep -E 'W4b ctx=|W5 ctx=' >"${OUT}/w4b-all.txt" || true
grep 'W4b ctx=write' "${OUT}/w4b-all.txt" >"${OUT}/w4b-write.txt" || true
grep 'W4b ctx=meta' "${OUT}/w4b-all.txt" >"${OUT}/w4b-meta.txt" || true
grep 'W5 ctx=' "${OUT}/w4b-all.txt" >"${OUT}/w5.txt" || true

# Normalize: phase fn kind reg val (drop seq/uid/timestamp for diff)
awk '
/W4b ctx=write/ {
  if (match($0, /phase=([^ ]+) fn=([^ ]+) kind=([^ ]+) reg=0x([0-9a-f]+) val=0x([0-9a-f]+)/, m)) {
    uid = "?";
    if (match($0, /uid=([0-9]+)/, u)) uid = u[1];
    print uid " " m[1] " " m[2] " " m[3] " " m[4] " " m[5];
  }
}
' "${OUT}/w4b-write.txt" >"${OUT}/w4b-write-norm.txt" || true

case "$WINDOW" in
boot)
	# Before first system_suspend
	awk '/phase=SUSPEND/ {exit} {print}' "${OUT}/w4b-write-norm.txt" >"${OUT}/w4b-window-norm.txt" 2>/dev/null || cp "${OUT}/w4b-write-norm.txt" "${OUT}/w4b-window-norm.txt"
	;;
resume)
	awk '/phase=RESUME/ || /phase=W5_MANUAL/ {p=1} p' "${OUT}/w4b-write-norm.txt" >"${OUT}/w4b-window-norm.txt" || true
	;;
playback)
	# RUNTIME + DAPM writes after last RESUME (or all if cold boot)
	if grep -q 'phase=RESUME' "${OUT}/w4b-write-norm.txt" 2>/dev/null; then
		awk 'BEGIN{r=0} / phase=RESUME / {r=1; next} r && (/ phase=RUNTIME / || / phase=DAPM /) {print}' \
			"${OUT}/w4b-write-norm.txt" >"${OUT}/w4b-window-norm.txt" || true
	else
		awk '/ phase=RUNTIME / || / phase=DAPM / {print}' "${OUT}/w4b-write-norm.txt" >"${OUT}/w4b-window-norm.txt" || true
	fi
	;;
all|*)
	cp "${OUT}/w4b-write-norm.txt" "${OUT}/w4b-window-norm.txt"
	;;
esac

echo "snapshot: $OUT"
echo "writes: $(wc -l <"${OUT}/w4b-write.txt" 2>/dev/null || echo 0)"
echo "window ($WINDOW): $(wc -l <"${OUT}/w4b-window-norm.txt" 2>/dev/null || echo 0)"
echo "Diff: ./scripts/w4-write-trace-diff.sh validation/w4b-write-pass-* validation/w4b-write-fail-s2-*"
