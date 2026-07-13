#!/usr/bin/env bash
# Diff W4 lifecycle sequences — find first missing or divergent step.
#
# Usage:
#   ./scripts/w4-trace-diff.sh validation/w4-trace-pass-cold-playback-* \\
#                               validation/w4-trace-fail-s2-playback-*
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <pass-dir> <fail-dir>" >&2
	exit 1
fi

PASS_DIR="$1"
FAIL_DIR="$2"

life_norm() {
	# Strip boot-time seq numbers; keep fn+phase for order compare
	sed -E 's/.*fn=([^ ]+) phase=([^ ]+).*/\1:\2/'
}

PASS_LIFE="${PASS_DIR}/w4-life.txt"
FAIL_LIFE="${FAIL_DIR}/w4-life.txt"

[[ -f "$PASS_LIFE" ]] || { echo "Missing $PASS_LIFE" >&2; exit 1; }
[[ -f "$FAIL_LIFE" ]] || { echo "Missing $FAIL_LIFE" >&2; exit 1; }

PASS_NORM="$(mktemp)"
FAIL_NORM="$(mktemp)"
trap 'rm -f "$PASS_NORM" "$FAIL_NORM"' EXIT

life_norm <"$PASS_LIFE" | sort -u >"$PASS_NORM"
life_norm <"$FAIL_LIFE" | sort -u >"$FAIL_NORM"

echo "=== W4 lifecycle — steps only in PASS ==="
comm -23 "$PASS_NORM" "$FAIL_NORM" || true
echo
echo "=== W4 lifecycle — steps only in FAIL ==="
comm -13 "$PASS_NORM" "$FAIL_NORM" || true
echo
echo "=== W4 readback diff (PDE23/PPU21/FU mute) ==="
diff -u "${PASS_DIR}/w4-readback.txt" "${FAIL_DIR}/w4-readback.txt" || true
echo
echo "=== Full life sequence diff (uid-agnostic fn:phase) ==="
diff -u "$PASS_NORM" "$FAIL_NORM" || true
