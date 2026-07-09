#!/usr/bin/env bash
# Phase 6 — state transition experiment (no kernel patches).
#
#   baseline [--notes N]
#   arm [--notes N]          # then: systemctl suspend
#   status
#   diff RUN_A RUN_B         # first divergence between two runs
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
	ARM_EPOCH="$(date +%s)"
	mkdir -p "$STATE_DIR"
	echo "$ARM_EPOCH" >"${STATE_DIR}/phase6-arm-epoch"
	pgrep -f 'phase6-chronology-capture.sh --wait-resume' >/dev/null && {
		echo "Worker already running." >&2; exit 1
	}
	nohup "${SCRIPT_DIR}/phase6-chronology-capture.sh" \
		--wait-resume "$ARM_EPOCH" \
		--notes "${NOTES:-phase6-controlled}" \
		>>"$WORKER_LOG" 2>&1 &
	echo $! >"${STATE_DIR}/phase6-worker.pid"
	echo "Phase 6 armed (PID $(cat "${STATE_DIR}/phase6-worker.pid")). Log: ${WORKER_LOG}"
	echo "Run: systemctl suspend"
	echo "Captures: 0, 0.5, 1, 2, 3, 5, 10, 20, 30, 60s + kmsg chronology"
	;;
status)
	echo "=== phase6 worker (tail) ==="
	tail -25 "$WORKER_LOG" 2>/dev/null || echo "(none)"
	for f in phase6-chronology.csv phase6-kmsg-events.csv resume-matrix.csv; do
		[[ -f "${REPO}/validation/$f" ]] || continue
		echo ""
		echo "=== validation/$f (tail) ==="
		tail -5 "${REPO}/validation/$f"
	done
	;;
diff)
	RUN_A="${1:?run A e.g. 0001}"; RUN_B="${2:?run B}"
	exec "${SCRIPT_DIR}/phase6-chronology-diff.sh" "$RUN_A" "$RUN_B"
	;;
*)
	head -10 "$0"
	exit 1
	;;
esac
