#!/usr/bin/env bash
# Controlled bifurcation experiment on a healthy boot (e.g. #41).
#
#   ./scripts/phase5-bifurcation-experiment.sh baseline [--notes N]
#   ./scripts/phase5-bifurcation-experiment.sh arm [--notes N]
#   ./scripts/phase5-bifurcation-experiment.sh status
#
# arm: snapshot baseline, fork 60s capture worker, then YOU run:
#   systemctl suspend
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/validation-metrics.sh
. "${SCRIPT_DIR}/lib/validation-metrics.sh"

STATE_DIR="${REPO}/validation/.state"
WORKER_LOG="${STATE_DIR}/bifurcation-worker.log"
NOTES=""

usage() {
	sed -n '2,10p' "$0"
	exit 0
}

cmd="${1:-}"
shift || true

while [[ $# -gt 0 ]]; do
	case "$1" in
	--notes) NOTES="${2:-}"; shift 2 ;;
	-h|--help) usage ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

case "$cmd" in
baseline)
	validation_metrics_init
	echo "=== Baseline $(date -Is) boot=$(cat /proc/sys/kernel/random/boot_id) ==="
	echo "  :8 attach=$(vm_attach_label "$VM_SDW_UID8") fw=$(vm_uid_fw_from_kmsg 8)"
	echo "  :b attach=$(vm_attach_label "$VM_SDW_UIDB") fw=$(vm_uid_fw_from_kmsg b)"
	echo "  rt721 attach=$(vm_attach_label "$VM_SDW_RT721")"
	echo "  pipewire=$(vm_pipewire_active) sink=$(vm_default_sink)"
	mkdir -p "$STATE_DIR"
	vm_dump_snapshot_verbose "${REPO}/validation/bifurcation-runs/baseline-$(date +%Y%m%d-%H%M%S)" 0 ""
	echo "Baseline captured. Next: $0 arm [--notes …] then systemctl suspend"
	;;
arm)
	ARM_EPOCH="$(date +%s)"
	mkdir -p "$STATE_DIR"
	echo "$ARM_EPOCH" >"${STATE_DIR}/bifurcation-arm-epoch"
	[[ -n "$NOTES" ]] && echo "$NOTES" >"${STATE_DIR}/bifurcation-arm-notes"

	# Avoid duplicate workers
	if pgrep -f 'phase5-bifurcation-capture.sh --wait-resume' >/dev/null 2>&1; then
		echo "Capture worker already running." >&2
		exit 1
	fi

	nohup "${SCRIPT_DIR}/phase5-bifurcation-capture.sh" \
		--wait-resume "$ARM_EPOCH" \
		--notes "${NOTES:-boot41-controlled}" \
		>>"$WORKER_LOG" 2>&1 &
	echo $! >"${STATE_DIR}/bifurcation-worker.pid"

	echo "Armed at epoch ${ARM_EPOCH}. Worker PID $(cat "${STATE_DIR}/bifurcation-worker.pid")."
	echo "Log: ${WORKER_LOG}"
	echo ""
	echo "Now run:  systemctl suspend"
	echo "After wake, worker samples at t=0,2,5,10,20,30,60s automatically."
	echo "Results: validation/bifurcation-timeline.csv + validation/bifurcation-runs/run-*/"
	;;
status)
	echo "Worker log (tail):"
	tail -20 "$WORKER_LOG" 2>/dev/null || echo "(no log yet)"
	if [[ -f "${REPO}/validation/bifurcation-timeline.csv" ]]; then
		echo ""
		echo "Latest timeline rows:"
		tail -8 "${REPO}/validation/bifurcation-timeline.csv"
	fi
	if [[ -f "${REPO}/validation/resume-matrix.csv" ]]; then
		echo ""
		echo "Latest resume-matrix:"
		tail -3 "${REPO}/validation/resume-matrix.csv"
	fi
	;;
*)
	usage
	;;
esac
