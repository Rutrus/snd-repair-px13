#!/usr/bin/env bash
# Snapshot TAS2783Q2 kernel trace lines for one boot window.
#
# Usage:
#   ./q2-fw-trace-collect.sh --label after-resume
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LABEL="snap"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="${2:?}"; shift 2 ;;
	-h | --help)
		echo "Usage: $0 [--label NAME]"
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
done

OUT_DIR="${Q2_TRACE_OUT:-$REPO_ROOT/validation/q2-fw-trace}"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="$OUT_DIR/${LABEL}-${STAMP}.log"

{
	echo "=== Q2 FW TRACE COLLECT ==="
	echo "label: $LABEL"
	echo "time: $(date -Iseconds)"
	echo "kernel: $(uname -r)"
	echo
	echo "=== TAS2783Q2 (full boot) ==="
	journalctl -k -b 0 --no-pager 2>/dev/null | grep TAS2783Q2 || echo "(no TAS2783Q2 lines — build build-q2-fw-trace.sh?)"
	echo
	echo "=== uid :8 ==="
	journalctl -k -b 0 --no-pager 2>/dev/null | grep TAS2783Q2 | grep ':8\|uid=0x8' || true
	echo
	echo "=== uid :b ==="
	journalctl -k -b 0 --no-pager 2>/dev/null | grep TAS2783Q2 | grep ':b\|uid=0xb' || true
	echo
	echo "=== FW errors (tas2783) ==="
	journalctl -k -b 0 --no-pager 2>/dev/null | \
		grep -E 'slave-tas2783|TAS2783Q2|playback without fw|fw download wait' || true
} | tee "$LOG"

echo "Wrote $LOG"
