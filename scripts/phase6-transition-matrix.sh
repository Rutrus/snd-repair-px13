#!/usr/bin/env bash
# Build Phase 6 transition matrix (PASS vs FAIL) from PHASE6 kernel traces.
#
# Usage:
#   ./scripts/phase6-transition-matrix.sh RUN_PASS RUN_FAIL
#   ./scripts/phase6-transition-matrix.sh --last-resume
#   ./scripts/phase6-transition-matrix.sh RUN_PASS RUN_FAIL --all-boot   # noisy, debug only
#
# Scope: one resume window (suspend_entry-5s … suspend_exit+15s) per run.
# PX13: RT721 = dev=3.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$REPO"
# shellcheck source=lib/phase6-journal.sh
. "${REPO}/scripts/lib/phase6-journal.sh"

EVENTS="${REPO}/validation/phase6-events.csv"
RT721_DEV="${PHASE6_RT721_DEV}"
SCOPE="resume_window"
RUN_PASS=""
RUN_FAIL=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--last-resume) RUN_PASS="last"; RUN_FAIL="last"; shift ;;
	--all-boot) SCOPE="all_boot"; shift ;;
	-h|--help)
		head -14 "$0"
		exit 0
		;;
	-*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	*)
		if [[ -z "$RUN_PASS" ]]; then
			RUN_PASS="$1"
		elif [[ -z "$RUN_FAIL" ]]; then
			RUN_FAIL="$1"
		else
			echo "Too many run ids" >&2
			exit 1
		fi
		shift
		;;
	esac
done

if [[ "$RUN_PASS" == "last" ]]; then
	RUN_PASS=""
	RUN_FAIL=""
fi

[[ -n "$RUN_PASS" && -n "$RUN_FAIL" ]] || true

lines_for() {
	local rid="${1:-}"
	if [[ -z "$rid" ]]; then
		phase6_lines_for_run "" "$SCOPE"
		return
	fi
	phase6_lines_for_run "$rid" "$SCOPE"
}

has_transition() {
	local pattern="$1"
	local lines="$2"
	echo "$lines" | grep -qE "$pattern" && echo "yes" || echo "no"
}

build_row_rt721() {
	local rid="${1:-}"
	local lines post
	lines="$(lines_for "$rid")"
	post="$(phase6_lines_post_manager_reset "$lines")"
	local r=""
	r+="$(has_transition "dev=${RT721_DEV}.*old=ATTACHED.*new=UNATTACHED" "$post")|"
	r+="$(has_transition "dev=${RT721_DEV}.*old=UNATTACHED.*new=ATTACHED" "$post")|"
	r+="$(has_transition "dev=${RT721_DEV}.*new=ALERT" "$lines")|"
	r+="$(has_transition "fn=completion.*dev=${RT721_DEV}" "$post")|"
	r+="$(has_transition "fn=state_skip.*dev=${RT721_DEV}.*already_attached" "$post")|"
	r+="$(has_transition "fn=state_skip.*dev=${RT721_DEV}.*from_alert" "$post")|"
	r+="$(has_transition 'fn=wait_init_ok' "$lines")|"
	r+="$(has_transition 'fn=branch_fast_path' "$lines")|"
	r+="$(has_transition 'fn=wait_init_timeout' "$lines")"
	echo "$r"
}

build_row_bus() {
	local rid="${1:-}"
	local lines post
	lines="$(lines_for "$rid")"
	post="$(phase6_lines_post_manager_reset "$lines")"
	local r=""
	r+="$(has_transition 'reason=manager_reset' "$lines")|"
	r+="$(has_transition 'dev=[123].*old=UNATTACHED.*new=ATTACHED' "$post")|"
	r+="$(has_transition 'fn=completion.*dev=[123]' "$post")"
	echo "$r"
}

mark() {
	[[ "$1" == "yes" ]] && echo "✅" || echo "❌"
}

print_matrix() {
	local title="$1"
	local pass_id="$2"
	local fail_id="$3"
	local pass_label fail_label

	if [[ -z "$pass_id" ]]; then
		pass_label="last-resume (current boot)"
		fail_label="(same window — single-column view)"
	else
		pass_label="$pass_id"
		fail_label="$fail_id"
	fi

	IFS='|' read -r P1 P2 P3 P4 P5 P6 P7 P8 P9 <<<"$(build_row_rt721 "$pass_id")"
	IFS='|' read -r F1 F2 F3 F4 F5 F6 F7 F8 F9 <<<"$(build_row_rt721 "$fail_id")"

	echo "=== ${title} (dev=${RT721_DEV} RT721, post manager_reset where noted) ==="
	echo "  PASS: ${pass_label}   FAIL: ${fail_label}"
	echo "  scope: ${SCOPE} (suspend_entry-${PHASE6_RESUME_PRE_S}s … suspend_exit+${PHASE6_RESUME_POST_S}s)"
	echo ""
	printf "| %-28s | %-4s | %-4s |\n" "Transition" "PASS" "FAIL"
	printf "|%-30s|%-6s|%-6s|\n" "------------------------------" "------" "------"
	printf "| %-28s | %-4s | %-4s |\n" "ATTACHED → UNATTACHED (reset)" "$(mark "$P1")" "$(mark "$F1")"
	printf "| %-28s | %-4s | %-4s |\n" "UNATTACHED → ATTACHED (post)" "$(mark "$P2")" "$(mark "$F2")"
	printf "| %-28s | %-4s | %-4s |\n" "→ ALERT (window)" "$(mark "$P3")" "$(mark "$F3")"
	printf "| %-28s | %-4s | %-4s |\n" "completion RT721 (post)" "$(mark "$P4")" "$(mark "$F4")"
	printf "| %-28s | %-4s | %-4s |\n" "state_skip already_attached" "$(mark "$P5")" "$(mark "$F5")"
	printf "| %-28s | %-4s | %-4s |\n" "state_skip from_alert" "$(mark "$P6")" "$(mark "$F6")"
	printf "| %-28s | %-4s | %-4s |\n" "wait_init_ok" "$(mark "$P7")" "$(mark "$F7")"
	printf "| %-28s | %-4s | %-4s |\n" "branch_fast_path" "$(mark "$P8")" "$(mark "$F8")"
	printf "| %-28s | %-4s | %-4s |\n" "wait_init_timeout" "$(mark "$P9")" "$(mark "$F9")"
	echo ""

	if [[ -n "$fail_id" && "$pass_id" != "$fail_id" ]]; then
		if [[ "$F2" == "no" && "$F5" == "no" && "$F1" == "yes" ]]; then
			echo "→ FAIL A: manager_reset but no post-reset ATTACHED/completion for RT721."
		elif [[ "$F2" == "no" && "$F5" == "yes" ]]; then
			echo "→ FAIL B: state_skip without completion — framework discarded ATTACHED."
		elif [[ "$F2" == "yes" && "$F4" == "no" ]]; then
			echo "→ ATTACHED logged but no completion — check from_alert or init path."
		fi
	fi

	IFS='|' read -r BP1 BP2 BP3 <<<"$(build_row_bus "$pass_id")"
	IFS='|' read -r BF1 BF2 BF3 <<<"$(build_row_bus "$fail_id")"
	echo "=== Global bus (post manager_reset) ==="
	printf "| %-28s | %-4s | %-4s |\n" "manager_reset in window" "$(mark "$BP1")" "$(mark "$BF1")"
	printf "| %-28s | %-4s | %-4s |\n" "any UNATTACHED→ATTACHED" "$(mark "$BP2")" "$(mark "$BF2")"
	printf "| %-28s | %-4s | %-4s |\n" "any completion dev=1..3" "$(mark "$BP3")" "$(mark "$BF3")"
	if [[ "$BF1" == "yes" && "$BF2" == "no" && "$BF3" == "no" ]]; then
		echo "→ Global bus stall after manager_reset (all slaves)."
	fi
	echo ""
}

if [[ -z "$RUN_PASS" ]]; then
	print_matrix "Phase 6 transition matrix (last resume)" "" ""
elif [[ "$RUN_PASS" == "$RUN_FAIL" ]]; then
	print_matrix "Phase 6 transition matrix (single run)" "$RUN_PASS" "$RUN_FAIL"
else
	print_matrix "Phase 6 transition matrix" "$RUN_PASS" "$RUN_FAIL"
fi

echo "PX13 map: dev=1 TAS2783:0xb  dev=2 TAS2783:0x8  dev=3 RT721:0xff"
echo "  ./scripts/phase6-state-machine.sh ${RUN_PASS:-} ${RUN_FAIL:-} [--last-resume]"
