#!/usr/bin/env bash
# Shared journal helpers for Phase 6 analysis scripts.
# shellcheck shell=bash

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# PX13 SoundWire enumeration (link 1):
#   dev=1 uid=0xb  TAS2783
#   dev=2 uid=0x8  TAS2783
#   dev=3 uid=0xff RT721
PHASE6_RT721_DEV="${PHASE6_RT721_DEV:-3}"
PHASE6_RESUME_PRE_S="${PHASE6_RESUME_PRE_S:-5}"
PHASE6_RESUME_POST_S="${PHASE6_RESUME_POST_S:-15}"

CHRONO_CSV="${REPO_ROOT}/validation/phase6-chronology.csv"
RUNS_DIR="${REPO_ROOT}/validation/phase6-runs"

# Resolve resume exit ISO timestamp for a run id (column resume_ts in chronology).
phase6_run_resume_ts() {
	local rid="${1:?run id}"
	[[ -f "$CHRONO_CSV" ]] || return 1
	awk -F, -v r="$rid" '$1==r {print $4; exit}' "$CHRONO_CSV"
}

phase6_run_proc_boot_id() {
	local rid="${1:?run id}"
	[[ -f "$CHRONO_CSV" ]] || return 1
	awk -F, -v r="$rid" '$1==r {print $3; exit}' "$CHRONO_CSV"
}

phase6_run_window_log() {
	local rid="${1:?run id}"
	local f="${RUNS_DIR}/run-${rid}/kmsg-phase6-window.log"
	[[ -f "$f" ]] && echo "$f"
}

# Last suspend entry / exit timestamps in current boot journal (short-precise fields).
phase6_journal_last_suspend_entry() {
	journalctl -k -b 0 --no-pager -o short-precise 2>/dev/null \
		| grep 'PM: suspend entry' | tail -1 | awk '{print $1" "$2" "$3}'
}

phase6_journal_last_suspend_exit() {
	journalctl -k -b 0 --no-pager -o short-precise 2>/dev/null \
		| grep 'PM: suspend exit' | tail -1 | awk '{print $1" "$2" "$3}'
}

# Given resume exit timestamp, find matching suspend entry in journal (same cycle).
phase6_journal_suspend_entry_before() {
	local resume_ts="${1:?resume exit ts}"
	journalctl -k -b 0 --no-pager -o short-precise --until "$resume_ts" 2>/dev/null \
		| grep 'PM: suspend entry' | tail -1 | awk '{print $1" "$2" "$3}'
}

# Compute --since / --until for a resume experiment window.
# Prints: SINCE<TAB>UNTIL on stdout.
phase6_resume_window_bounds() {
	local resume_exit_ts="${1:?resume exit}"
	local entry_ts since until
	entry_ts="$(phase6_journal_suspend_entry_before "$resume_exit_ts")"
	if [[ -z "$entry_ts" ]]; then
		entry_ts="$(date -d "$resume_exit_ts - ${PHASE6_RESUME_PRE_S} seconds" '+%b %e %H:%M:%S.%N' 2>/dev/null \
			| sed 's/  / /g' || date -d "$resume_exit_ts - ${PHASE6_RESUME_PRE_S} seconds" '+%Y-%m-%d %H:%M:%S')"
	fi
	since="$(date -d "$entry_ts - ${PHASE6_RESUME_PRE_S} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
		|| date -d "$entry_ts - ${PHASE6_RESUME_PRE_S} seconds" '+%Y-%m-%d %H:%M:%S')"
	until="$(date -d "$resume_exit_ts + ${PHASE6_RESUME_POST_S} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
		|| date -d "$resume_exit_ts + ${PHASE6_RESUME_POST_S} seconds" '+%Y-%m-%d %H:%M:%S')"
	printf '%s\t%s\n' "$since" "$until"
}

# Extract kernel PHASE6 (+ PM anchors) lines for one resume window.
phase6_journal_extract_window() {
	local resume_exit_ts="${1:?resume exit ts}"
	local bounds since until
	bounds="$(phase6_resume_window_bounds "$resume_exit_ts")"
	since="${bounds%%$'\t'*}"
	until="${bounds#*$'\t'}"
	journalctl -k -b 0 --no-pager -o short-precise \
		--since "$since" --until "$until" 2>/dev/null \
		| grep -E 'PHASE6 ctx=|PM: suspend (entry|exit)' || true
}

# Save resume-window log for offline analysis (cross-boot safe).
phase6_save_run_window_log() {
	local rid="${1:?run id}" resume_ts="${2:?resume exit ts}"
	local out="${RUNS_DIR}/run-${rid}/kmsg-phase6-window.log"
	local bounds since until meta="${RUNS_DIR}/run-${rid}/meta.txt"
	mkdir -p "${RUNS_DIR}/run-${rid}"
	bounds="$(phase6_resume_window_bounds "$resume_ts")"
	since="${bounds%%$'\t'*}"
	until="${bounds#*$'\t'}"
	phase6_journal_extract_window "$resume_ts" >"$out"
	{
		echo "resume_ts=${resume_ts}"
		echo "window_since=${since}"
		echo "window_until=${until}"
	} >>"$meta"
	echo "$out"
}

# Lines for analysis tools.
# Priority: saved window log → live journal window (same boot) → warn + empty.
# mode: resume_window (default) | all_boot
phase6_lines_for_run() {
	local rid="${1:-}"
	local mode="${2:-resume_window}"

	if [[ -n "$rid" ]]; then
		local saved
		saved="$(phase6_run_window_log "$rid" || true)"
		if [[ -n "$saved" ]]; then
			cat "$saved"
			return 0
		fi

		local resume_ts boot_id cur_boot
		resume_ts="$(phase6_run_resume_ts "$rid" || true)"
		boot_id="$(phase6_run_proc_boot_id "$rid" || true)"
		cur_boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "")"

		if [[ -z "$resume_ts" ]]; then
			echo "WARN: run ${rid}: no resume_ts in ${CHRONO_CSV} and no saved window log" >&2
			return 0
		fi

		if [[ -n "$boot_id" && -n "$cur_boot" && "$boot_id" != "$cur_boot" ]]; then
			echo "WARN: run ${rid} is from boot ${boot_id}; current boot is ${cur_boot}." >&2
			echo "WARN: re-capture with phase6 arm or restore ${RUNS_DIR}/run-${rid}/kmsg-phase6-window.log" >&2
			return 0
		fi

		phase6_journal_extract_window "$resume_ts"
		return 0
	fi

	case "$mode" in
	all_boot)
		journalctl -k -b 0 --no-pager 2>/dev/null \
			| grep -E 'PHASE6 ctx=|PM: suspend (entry|exit)' || true
		;;
	resume_window|*)
		local exit_ts
		exit_ts="$(phase6_journal_last_suspend_exit)"
		if [[ -z "$exit_ts" ]]; then
			echo "WARN: no PM: suspend exit in current boot" >&2
			return 0
		fi
		phase6_journal_extract_window "$exit_ts"
		;;
	esac
}

# Keep only events at or after the last manager_reset in a window (resume cycle focus).
phase6_lines_post_manager_reset() {
	local lines="${1:-}"
	local out=""
	local past=0
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		if echo "$line" | grep -q 'reason=manager_reset'; then
			past=1
		fi
		[[ "$past" -eq 1 ]] && out+="${line}"$'\n'
	done <<<"$lines"
	# If no manager_reset in window (runtime PM resume), return full window.
	if [[ "$past" -eq 0 ]]; then
		printf '%s' "$lines"
	else
		printf '%s' "$out"
	fi
}
