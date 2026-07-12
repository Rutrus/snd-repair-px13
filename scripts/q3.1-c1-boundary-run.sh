#!/usr/bin/env bash
# Q3.1 Phase A — C1 boundary with high-confidence witnesses (same boot).
#
# Does NOT apply 0006a. Captures /proc/interrupts + kernel trace + analyzer.
#
# Prereq (recommended):
#   sudo ./scripts/build-q3-trace.sh
#   sudo ./scripts/build-phase8.sh    # handler_since_pm + irq_stats
#   sudo reboot
#
# Usage:
#   ./scripts/q3.1-c1-boundary-run.sh [--label NAME] [--skip-suspend]
#   ./scripts/q3.1-c1-boundary-run.sh --collect-only   # after manual suspend
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LABEL="c1-boundary"
SKIP_SUSPEND=0
COLLECT_ONLY=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="${2:?}"; shift 2 ;;
	--skip-suspend) SKIP_SUSPEND=1; shift ;;
	--collect-only) COLLECT_ONLY=1; shift ;;
	-h | --help)
		cat <<EOF
Usage: $0 [--label NAME] [--skip-suspend] [--collect-only]

Q3.1 Phase A: pre/post /proc/interrupts + q3 collect/analyze + irq compare.
Does not run 0006a intervention.

Recommended build: build-q3-trace.sh + build-phase8.sh, then reboot.
EOF
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
done

if [[ "$COLLECT_ONLY" -eq 0 && "$SKIP_SUSPEND" -eq 0 ]]; then
	echo "==> Q3.1 C1: pre-suspend /proc/interrupts"
	"$SCRIPT_DIR/phase8-irq-snapshot.sh" pre-suspend
	echo ""
	echo "==> Suspending (systemctl suspend) — wake machine to continue"
	systemctl suspend || true
	echo "==> Waiting for resume settle..."
	sleep 5
fi

echo "==> Q3.1 C1: post-resume /proc/interrupts"
"$SCRIPT_DIR/phase8-irq-snapshot.sh" post-resume
echo ""
echo "==> Q3.1 C1: interrupt compare"
"$SCRIPT_DIR/phase8-irq-snapshot.sh" compare || true
echo ""

LOG="$("$SCRIPT_DIR/q3-sdw-reattach-collect.sh" --label "$LABEL" 2>&1 | tee /dev/stderr | sed -n 's/^Wrote //p' | tail -1)"
[[ -n "$LOG" && -f "$LOG" ]] || LOG="$(ls -t "$REPO_ROOT"/validation/q3-sdw-reattach/"${LABEL}"-*.log 2>/dev/null | head -1 || true)"

echo "==> Q3.1 analyzer"
"$SCRIPT_DIR/q3-sdw-reattach-analyze.sh" "$LOG"

echo ""
echo "==> PHASE8 irq_stats (if module built with 0008):"
journalctl -k -b 0 --no-pager 2>/dev/null | grep 'PHASE8 ctx=acp fn=irq_stats' | tail -5 || echo "(none — run: sudo ./scripts/build-phase8.sh && reboot)"

echo ""
echo "Done. Fill S0 vs S2 table in research/q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md"
