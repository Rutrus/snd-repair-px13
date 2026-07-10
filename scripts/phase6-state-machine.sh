#!/usr/bin/env bash
# Extract PHASE6 state machines from saved resume window or journal.
#
# Usage:
#   ./scripts/phase6-state-machine.sh --last-resume     # default: last resume window
#   ./scripts/phase6-state-machine.sh RUN_ID
#   ./scripts/phase6-state-machine.sh RUN_PASS RUN_FAIL
#   ./scripts/phase6-state-machine.sh --all-boot        # debug: full boot (noisy)
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$REPO"
# shellcheck source=lib/phase6-journal.sh
. "${REPO}/scripts/lib/phase6-journal.sh"
# shellcheck source=lib/phase6-resume-summary.sh
. "${REPO}/scripts/lib/phase6-resume-summary.sh"

SCOPE="resume_window"
ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	--last-resume) SCOPE="resume_window"; shift ;;
	--all-boot) SCOPE="all_boot"; shift ;;
	-h|--help)
		head -12 "$0"
		exit 0
		;;
	*) ARGS+=("$1"); shift ;;
	esac
done

set -- "${ARGS[@]}"

normalize_machine() {
	grep -E 'PHASE6 ctx=(sdw|pm|init|amd)|PM: suspend (entry|exit)' | while IFS= read -r line; do
		if echo "$line" | grep -q 'PM: suspend entry'; then
			echo "  pm  suspend_entry"
		elif echo "$line" | grep -q 'PM: suspend exit'; then
			echo "  pm  suspend_exit"
		elif echo "$line" | grep -q 'fn=state_change'; then
			old="$(echo "$line" | sed -n 's/.*old=\([A-Z]*\).*/\1/p')"
			new="$(echo "$line" | sed -n 's/.*new=\([A-Z]*\).*/\1/p')"
			reason="$(echo "$line" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')"
			dev="$(echo "$line" | sed -n 's/.*dev=\([0-9]*\).*/\1/p')"
			uid="$(echo "$line" | sed -n 's/.*uid=0x\([0-9a-f]*\).*/\1/p')"
			[[ -z "$dev" ]] && dev="?"
			tag=""
			[[ "$dev" == "${PHASE6_RT721_DEV}" ]] && tag=" RT721"
			echo "  sdw dev=${dev} uid=0x${uid:-?}${tag}  ${old} → ${new}  (${reason})"
		elif echo "$line" | grep -q 'fn=completion'; then
			dev="$(echo "$line" | sed -n 's/.*dev=\([0-9]*\).*/\1/p')"
			el="$(echo "$line" | sed -n 's/.*elapsed_ms=\(-*[0-9]*\).*/\1/p')"
			ph="$(echo "$line" | sed -n 's/.*phase=\([^ ]*\).*/\1/p')"
			[[ -z "$ph" && "$el" == "-1" ]] && ph="boot"
			echo "  sdw dev=${dev}  completion  elapsed_ms=${el:-?}${ph:+ phase=${ph}}"
		elif echo "$line" | grep -q 'fn=state_skip'; then
			dev="$(echo "$line" | sed -n 's/.*dev=\([0-9]*\).*/\1/p')"
			reason="$(echo "$line" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')"
			echo "  sdw dev=${dev}  SKIP  (${reason})"
		elif echo "$line" | grep -qE 'ctx=amd fn='; then
			fn="$(echo "$line" | sed -n 's/.*fn=\([^ ]*\).*/\1/p')"
			rest="$(echo "$line" | sed 's/.*PHASE6 ctx=amd //')"
			echo "  amd  ${fn}  ${rest}"
		elif echo "$line" | grep -qE 'ctx=acp fn='; then
			fn="$(echo "$line" | sed -n 's/.*fn=\([^ ]*\).*/\1/p')"
			rest="$(echo "$line" | sed 's/.*PHASE6 ctx=acp //')"
			echo "  acp  ${fn}  ${rest}"
		elif echo "$line" | grep -q 'fn=wait_init_start'; then
			echo "  rt721  wait_init_start"
		elif echo "$line" | grep -q 'fn=wait_init_ok'; then
			echo "  rt721  wait_init_ok"
		elif echo "$line" | grep -q 'fn=wait_init_timeout'; then
			echo "  rt721  wait_init_timeout"
		elif echo "$line" | grep -q 'fn=resume_early_exit'; then
			reason="$(echo "$line" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')"
			echo "  rt721  resume_early_exit  reason=${reason:-?}"
		elif echo "$line" | grep -q 'fn=branch_fast_path'; then
			echo "  rt721  branch_fast_path"
		elif echo "$line" | grep -q 'fn=resume_exit'; then
			ret="$(echo "$line" | sed -n 's/.*ret=\(-*[0-9]*\).*/\1/p')"
			echo "  rt721  resume_exit  ret=${ret:-?}"
		fi
	done
}

lines_for_run() {
	local rid="${1:-}"
	phase6_lines_for_run "$rid" "$SCOPE"
}

print_machine() {
	local title="$1"
	local rid="${2:-}"
	echo "=== ${title} ==="
	echo "  scope: ${SCOPE}"
	lines_for_run "$rid" | normalize_machine
	echo ""
	phase6_resume_path_summary "$rid"
}

case $# in
0)
	print_machine "State machine (last resume window, boot 0)" ""
	;;
1)
	print_machine "Run ${1} (resume window)" "$1"
	;;
2)
	print_machine "Run ${1} (PASS candidate)" "$1"
	print_machine "Run ${2} (FAIL candidate)" "$2"
	echo "Compare Resume path blocks above (post manager_reset)."
	;;
*)
	echo "Usage: $0 [RUN_ID] [RUN_B] [--last-resume|--all-boot]" >&2
	exit 1
	;;
esac

echo "PX13: dev=1,2 TAS2783  dev=${PHASE6_RT721_DEV} RT721"
