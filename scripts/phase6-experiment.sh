#!/usr/bin/env bash
# Phase 6 — state transition experiment (no kernel patches).
#
#   baseline [--notes N]
#   arm [--notes N]          # then: systemctl suspend
#   sm | state-machine       # last resume window
#
# PASS hunt workflow: scripts/phase6-hunt.sh post-reboot | post-suspend
#   status
#   diff RUN_A RUN_B         # first diverging event (all layers)
#   diagram RUN_ID           # ASCII timeline
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/validation-metrics.sh
. "${SCRIPT_DIR}/lib/validation-metrics.sh"

STATE_DIR="${REPO}/validation/.state"
WORKER_LOG="${STATE_DIR}/phase6-worker.log"
NOTES=""

cmd="${1:-}"
shift || true
while [[ $# -gt 0 ]]; do
	case "$1" in
	--notes) NOTES="${2:-}"; shift 2 ;;
	-h|--help) head -10 "$0"; exit 0 ;;
	*) break ;;
	esac
done

phase6_stop_workers() {
	local p
	p="$(pgrep -f 'phase6-chronology-capture.sh --wait-resume' 2>/dev/null || true)"
	if [[ -n "$p" ]]; then
		echo "Stopping phase6 worker(s): $p"
		pkill -f 'phase6-chronology-capture.sh --wait-resume' 2>/dev/null || true
		sleep 0.3
	fi
	rm -f "${STATE_DIR}/phase6-worker.pid"
}

phase6_worker_running() {
	pgrep -f 'phase6-chronology-capture.sh --wait-resume' >/dev/null 2>&1
}

case "$cmd" in
baseline)
	validation_metrics_init
	echo "=== Phase 6 baseline $(date -Is) ==="
	echo "  boot_id=$(cat /proc/sys/kernel/random/boot_id)"
	echo "  load1=$(awk '{print $1}' /proc/loadavg)"
	echo "  :8  attach=$(vm_attach_label "$VM_SDW_UID8") fw=$(vm_uid_fw_from_kmsg 8)"
	echo "  :b  attach=$(vm_attach_label "$VM_SDW_UIDB") fw=$(vm_uid_fw_from_kmsg b)"
	echo "  rt721 attach=$(vm_attach_label "$VM_SDW_RT721")"
	echo "  pipewire=$(vm_pipewire_active) sink=$(vm_default_sink)"
	vm_dump_snapshot_verbose "${REPO}/validation/phase6-runs/baseline-$(date +%Y%m%d-%H%M%S)" 0 ""
	echo ""
	echo "Next: $0 arm [--notes …]  →  systemctl suspend"
	;;
arm)
	ARM_FORCE=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--force|-f) ARM_FORCE=1; shift ;;
		*) break ;;
		esac
	done
	ARM_EPOCH="$(date +%s)"
	mkdir -p "$STATE_DIR"
	echo "$ARM_EPOCH" >"${STATE_DIR}/phase6-arm-epoch"
	if phase6_worker_running; then
		if [[ "$ARM_FORCE" -eq 1 ]]; then
			phase6_stop_workers
		else
			echo "Worker already running (capture takes up to ~60s after resume)." >&2
			echo "  status: $0 status" >&2
			echo "  stop:   $0 disarm   or   $0 arm --force [--notes …]" >&2
			exit 1
		fi
	fi
	nohup "${SCRIPT_DIR}/phase6-chronology-capture.sh" \
		--wait-resume "$ARM_EPOCH" \
		--notes "${NOTES:-phase6-controlled}" \
		>>"$WORKER_LOG" 2>&1 &
	echo $! >"${STATE_DIR}/phase6-worker.pid"
	echo "Phase 6 armed (PID $(cat "${STATE_DIR}/phase6-worker.pid")). Log: ${WORKER_LOG}"
	if [[ "${PHASE6_SKIP_PX13:-0}" == "1" ]]; then
		echo "PHASE6_SKIP_PX13=1 — consider: sudo systemctl mask --runtime px13-audio-fix.service"
	fi
	echo "Run: systemctl suspend"
	echo "Captures: 0…60s + 3-layer events + diagram.txt"
	;;
disarm|stop)
	phase6_stop_workers
	echo "Phase 6 worker stopped."
	;;
status)
	echo "=== phase6 worker (tail) ==="
	tail -25 "$WORKER_LOG" 2>/dev/null || echo "(none)"
	for f in phase6-chronology.csv phase6-events.csv phase6-kmsg-events.csv resume-matrix.csv; do
		[[ -f "${REPO}/validation/$f" ]] || continue
		echo ""
		echo "=== validation/$f (tail) ==="
		tail -5 "${REPO}/validation/$f"
	done
	;;
diff)
	RUN_A="${1:?run A e.g. 0001}"; RUN_B="${2:?run B}"
	exec "${SCRIPT_DIR}/phase6-first-divergence.sh" "$RUN_A" "$RUN_B"
	;;
state-machine|sm)
	exec "${SCRIPT_DIR}/phase6-state-machine.sh" "$@"
	;;
matrix)
	exec "${SCRIPT_DIR}/phase6-transition-matrix.sh" "$@"
	;;
timeline|tl)
	exec "${SCRIPT_DIR}/phase6-resume-timeline.sh" "$@"
	;;
window)
	# Extract/save resume window log for a run or last resume.
	RID="${1:-}"
	# shellcheck source=lib/phase6-journal.sh
	. "${SCRIPT_DIR}/lib/phase6-journal.sh"
	REPO_ROOT="$REPO"
	if [[ -n "$RID" ]]; then
		ts="$(phase6_run_resume_ts "$RID")" || exit 1
		phase6_save_run_window_log "$RID" "$ts"
	else
		ts="$(phase6_journal_last_suspend_exit)" || { echo "No suspend exit" >&2; exit 1; }
		phase6_journal_extract_window "$ts"
	fi
	;;
diagram)
	RUN_ID="${1:?run_id}"
	exec "${SCRIPT_DIR}/phase6-timeline-diagram.sh" "$RUN_ID"
	;;
*)
	head -10 "$0"
	exit 1
	;;
esac
