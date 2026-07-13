#!/usr/bin/env bash
# Extract W4 kernel trace lines from current boot for PASS vs FAIL diff.
#
# Usage:
#   sudo ./scripts/w4-trace-capture.sh --label pass-cold-playback
#   sudo ./scripts/w4-trace-capture.sh --label fail-s2-playback
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
LABEL=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="$2"; shift 2 ;;
	-h|--help) sed -n '3,8p' "$0"; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date +%Y%m%d-%H%M%S)"
TAG="${LABEL:+$LABEL-}${TS}"
OUT="${REPO}/validation/w4-trace-${TAG}"
mkdir -p "$OUT"

{
	echo "time=$(date -Iseconds) label=${LABEL:-none}"
	echo "kernel=$(uname -r)"
	echo "suspend_count=$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -c 'PM: suspend entry' || true)"
} >"${OUT}/meta.txt"

journalctl -k -b 0 --no-pager 2>/dev/null \
	| grep -E 'W4 ctx=' \
	| tee "${OUT}/w4-all.txt" >/dev/null

grep 'W4 ctx=life' "${OUT}/w4-all.txt" >"${OUT}/w4-life.txt" || true
grep 'W4 ctx=rb' "${OUT}/w4-all.txt" >"${OUT}/w4-readback.txt" || true
grep 'W4 ctx=sdca' "${OUT}/w4-all.txt" >"${OUT}/w4-sdca.txt" || true

# Per-uid lifecycle (uid 8 / 11 on PX13)
for uid in 8 11 b; do
	grep "uid=${uid} " "${OUT}/w4-life.txt" >"${OUT}/w4-life-uid${uid}.txt" 2>/dev/null || true
done

echo "snapshot: $OUT"
echo "life lines: $(wc -l <"${OUT}/w4-life.txt" 2>/dev/null || echo 0)"
echo "Diff: ./scripts/w4-trace-diff.sh validation/w4-trace-pass-* validation/w4-trace-fail-*"
