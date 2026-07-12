#!/usr/bin/env bash
# Q3 — collect SoundWire re-attach + TAS2783Q2 trace for one resume window.
#
# Requires on kernel (at least one):
#   - PHASE6 patches (0002 bus + 0003 amd) — scripts/build-phase6-*.sh
#   - TAS2783Q2 trace — scripts/build-q2-fw-trace.sh
#
# Usage:
#   ./scripts/q3-sdw-reattach-collect.sh [--label after-resume]
#   ./scripts/q3-sdw-reattach-collect.sh --all-boot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/phase6-journal.sh
. "${SCRIPT_DIR}/lib/phase6-journal.sh"

LABEL="snap"
MODE="resume_window"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="${2:?}"; shift 2 ;;
	--all-boot) MODE="all_boot"; shift ;;
	-h | --help)
		cat <<EOF
Usage: $0 [--label NAME] [--all-boot]

Collect Q3 evidence for first missing SoundWire re-attach transition.
Default: last suspend/resume window on current boot.

Output: validation/q3-sdw-reattach/<label>-<stamp>.log
Then:   ./scripts/q3-sdw-reattach-analyze.sh <log>
EOF
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
done

OUT_DIR="${Q3_TRACE_OUT:-$REPO_ROOT/validation/q3-sdw-reattach}"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="$OUT_DIR/${LABEL}-${STAMP}.log"

extract_lines() {
	if [[ "$MODE" == "all_boot" ]]; then
		journalctl -k -b 0 --no-pager -o short-precise 2>/dev/null || true
	else
		local exit_ts
		exit_ts="$(phase6_journal_last_suspend_exit)"
		if [[ -z "$exit_ts" ]]; then
			echo "WARN: no PM: suspend exit — use --all-boot or suspend first" >&2
			journalctl -k -b 0 --no-pager -o short-precise 2>/dev/null || true
			return
		fi
		local bounds since until
		bounds="$(phase6_resume_window_bounds "$exit_ts")"
		since="${bounds%%$'\t'*}"
		until="${bounds#*$'\t'}"
		journalctl -k -b 0 --no-pager -o short-precise \
			--since "$since" --until "$until" 2>/dev/null || true
	fi
}

{
	echo "=== Q3 SDW RE-ATTACH COLLECT ==="
	echo "label: $LABEL"
	echo "mode: $MODE"
	echo "time: $(date -Iseconds)"
	echo "kernel: $(uname -r)"
	echo "boot_id: $(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
	echo

	ALL="$(extract_lines)"

	echo "=== PM anchors ==="
	echo "$ALL" | grep -E 'PM: suspend (entry|exit)|PM: failed to resume' || echo "(none)"
	echo

	echo "=== PHASE6 (manager / bus / AMD) ==="
	echo "$ALL" | grep -E 'PHASE[67] ctx=' || echo "(none — build phase6 0002+0003?)"
	echo

	echo "=== SoundWire state_change (post manager_reset) ==="
	phase6_lines_post_manager_reset "$ALL" \
		| grep -E 'PHASE6 ctx=sdw fn=state_change|PHASE6 ctx=sdw fn=completion|PHASE6 ctx=sdw fn=state_skip' \
		|| echo "$ALL" | grep -E 'state_change.*ATTACHED|state_change.*UNATTACHED|fn=completion' || echo "(none)"
	echo

	echo "=== initialization_complete / PM -110 (slaves) ==="
	echo "$ALL" | grep -E 'initialization timed out|failed to resume: error -110|wait_init' || echo "(none)"
	echo

	echo "=== TAS2783Q2 (codec state ladder) ==="
	echo "$ALL" | grep TAS2783Q2 || echo "(none — build-q2-fw-trace.sh?)"
	echo

	echo "=== Bus alive signals (master_port / program) ==="
	echo "$ALL" | grep -E 'master_port OK|sdw_program|ENZODBG.*slave_port OK' | head -40 || echo "(none)"
	echo

	echo "=== PHASE8 irq_stats (handler_since_pm — C1 boundary) ==="
	echo "$ALL" | grep -E 'PHASE8 ctx=acp fn=irq_stats' || echo "(none — build-phase8.sh + reboot?)"
	echo

	echo "=== hw_params / FW timeout (:8) ==="
	echo "$ALL" | grep -E 'fw download wait timeout|playback without fw|hw_params wait|TAS2783Q2 fn=hw_params' || echo "(none)"
} | tee "$LOG"

echo "Wrote $LOG"
echo "Analyze: ${SCRIPT_DIR}/q3-sdw-reattach-analyze.sh $LOG"
