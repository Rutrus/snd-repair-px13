#!/usr/bin/env bash
# Compare capture client matrix: cold boot vs post-S2 (Branch B baseline).
#
# Usage:
#   # After cold boot (no suspend since boot):
#   ./scripts/capture-access-cold-vs-s2.sh --phase cold
#
#   # After systemctl suspend && resume:
#   ./scripts/capture-access-cold-vs-s2.sh --phase post-s2
#
#   # Both devices (DMIC + RT721):
#   ./scripts/capture-access-cold-vs-s2.sh --phase post-s2 --all-devices
#
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PHASE=""
ALL_DEV=0
RECORD_SEC="${MATRIX_RECORD_SEC:-2}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--phase) PHASE="$2"; shift 2 ;;
	--all-devices) ALL_DEV=1; shift ;;
	--record-sec) RECORD_SEC="$2"; shift 2 ;;
	-h|--help)
		sed -n '3,16p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

[[ -n "$PHASE" ]] || { echo "FAIL: --phase cold|post-s2 required" >&2; exit 1; }
[[ "$PHASE" == cold || "$PHASE" == post-s2 ]] || {
	echo "FAIL: phase must be cold or post-s2" >&2; exit 1
}

TS_FILE="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${REPO}/validation/capture-access-baseline-${PHASE}-${TS_FILE}"
mkdir -p "$OUT_DIR"

exec > >(tee "${OUT_DIR}/run.log") 2>&1

echo "=== CAPTURE ACCESS BASELINE ($PHASE) ==="
echo "time=$(date -Iseconds) kernel=$(uname -r)"
echo "output_dir=$OUT_DIR"
echo

if [[ "$PHASE" == cold ]]; then
	echo "NOTE: run this phase immediately after boot (before any suspend)."
else
	echo "NOTE: run this phase after at least one systemctl suspend → resume."
fi
echo

_run_one() {
	local dev="$1" fmt="$2" tag="$3"
	local sub="${OUT_DIR}/${tag}"
	mkdir -p "$sub"
	echo "========== $tag ($dev $fmt) =========="
	MATRIX_RECORD_SEC="$RECORD_SEC" MATRIX_CONTEXT="$PHASE" \
		"$SCRIPT_DIR/capture-client-access-matrix.sh" \
		--context "$PHASE" --device "$dev" --format "$fmt" --out-dir "$sub"
	echo
}

_run_one hw:1,4 S32_LE dmic-hw14

if [[ "$ALL_DEV" -eq 1 ]]; then
	_run_one hw:1,1 S16_LE rt721-hw11
fi

{
	echo "# Capture access baseline — $PHASE"
	echo
	echo "time=$(date -Iseconds)"
	echo
	for sub in "${OUT_DIR}"/dmic-hw14 "${OUT_DIR}"/rt721-hw11; do
		[[ -d "$sub" ]] || continue
		echo "## $(basename "$sub")"
		[[ -f "$sub/summary.md" ]] && cat "$sub/summary.md"
		echo
	done
	echo "Compare cold vs post-s2:"
	echo '  diff -ru validation/capture-access-baseline-cold-*/ validation/capture-access-baseline-post-s2-*/'
} | tee "${OUT_DIR}/INDEX.md"

echo "baseline complete: $OUT_DIR"
