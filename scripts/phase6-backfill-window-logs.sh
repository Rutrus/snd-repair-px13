#!/usr/bin/env bash
# Backfill kmsg-phase6-window.log for runs captured before window logging existed.
#
# Usage:
#   ./scripts/phase6-backfill-window-logs.sh [RUN_ID ...]
#   ./scripts/phase6-backfill-window-logs.sh --all
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$REPO"
# shellcheck source=lib/phase6-journal.sh
. "${SCRIPT_DIR}/lib/phase6-journal.sh"

runs=()
if [[ "${1:-}" == "--all" ]]; then
	mapfile -t runs < <(awk -F, 'NR>1 {print $1}' "$CHRONO_CSV" | sort -u)
elif [[ $# -gt 0 ]]; then
	runs=("$@")
else
	echo "Usage: $0 RUN_ID [RUN_ID ...] | --all" >&2
	exit 1
fi

cur_boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "")"
for rid in "${runs[@]}"; do
	resume_ts="$(phase6_run_resume_ts "$rid" || true)"
	[[ -n "$resume_ts" ]] || { echo "skip ${rid}: no resume_ts"; continue; }
	boot_id="$(phase6_run_proc_boot_id "$rid" || true)"
	if [[ -n "$boot_id" && -n "$cur_boot" && "$boot_id" != "$cur_boot" ]]; then
		echo "skip ${rid}: boot ${boot_id} != current ${cur_boot} (journal lost)"
		continue
	fi
	out="$(phase6_save_run_window_log "$rid" "$resume_ts")"
	lines="$(wc -l <"$out")"
	echo "run-${rid}: ${lines} lines → ${out}"
done
