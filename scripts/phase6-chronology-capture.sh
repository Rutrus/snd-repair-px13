#!/usr/bin/env bash
# High-resolution resume chronology (Phase 6).
# Samples: 0, 0.5, 1, 2, 3, 5, 10, 20, 30, 60 s from PM suspend exit.
#
#   --wait-resume EPOCH   (worker mode, from phase6-experiment.sh arm)
#   --from-last-resume    (manual, resume already happened)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/validation-metrics.sh
. "${SCRIPT_DIR}/lib/validation-metrics.sh"

CHRONO="${REPO}/validation/phase6-chronology.csv"
RUNS="${REPO}/validation/phase6-runs"
STATE_DIR="${REPO}/validation/.state"
TEMPLATE="${REPO}/research/phase-6/templates/resume-chronology.csv"
# seconds (fractional)
OFFSETS=(0 0.5 1 2 3 5 10 20 30 60)
NOTES=""
FROM_LAST=0
WAIT_RESUME=0
ARM_EPOCH=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--notes) NOTES="${2:-}"; shift 2 ;;
	--from-last-resume) FROM_LAST=1; shift ;;
	--wait-resume) WAIT_RESUME=1; ARM_EPOCH="${2:?epoch}"; shift 2 ;;
	-h|--help)
		head -8 "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

mkdir -p "$RUNS" "$STATE_DIR"
[[ -f "$CHRONO" ]] || cp "$TEMPLATE" "$CHRONO"

kmsg_resume_ts() {
	journalctl -k -b 0 --no-pager -g 'PM: suspend exit' 2>/dev/null | tail -1 \
		| awk '{print $1,$2,$3}'
}

wait_for_resume_after() {
	local arm="$1" ts line epoch
	while true; do
		line="$(journalctl -k -b 0 --no-pager -g 'PM: suspend exit' 2>/dev/null | tail -1 || true)"
		ts="$(echo "$line" | awk '{print $1,$2,$3}')"
		[[ -z "$ts" || "$ts" == "  " ]] && { sleep 0.2; continue; }
		epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
		if [[ "$epoch" -gt "$arm" ]]; then
			echo "$ts"
			return 0
		fi
		sleep 0.2
	done
}

next_run_id() {
	local f="$STATE_DIR/phase6-run-seq"
	local n=1
	[[ -f "$f" ]] && n=$(( $(cat "$f") + 1 ))
	echo "$n" >"$f"
	printf '%04d' "$n"
}

if [[ "$WAIT_RESUME" -eq 1 ]]; then
	echo "phase6-chrono: waiting for resume after arm epoch ${ARM_EPOCH}..."
	RESUME_TS="$(wait_for_resume_after "$ARM_EPOCH")"
else
	RESUME_TS="$(kmsg_resume_ts)"
	[[ -n "$RESUME_TS" && "$RESUME_TS" != "  " ]] || {
		echo "No PM suspend exit this boot." >&2
		exit 1
	}
	[[ "$FROM_LAST" -eq 1 ]] || {
		echo "Use --from-last-resume or --wait-resume." >&2
		exit 1
	}
fi

RESUME_ISO="$(date -d "$RESUME_TS" -Is 2>/dev/null | cut -d+ -f1)"
RESUME_EPOCH="$(date -d "$RESUME_TS" +%s)"
PROC_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
RUN_ID="$(next_run_id)"
RUN_DIR="${RUNS}/run-${RUN_ID}"
mkdir -p "$RUN_DIR"

BOOT_ID="?"
[[ -f "${REPO}/validation/fw-matrix.csv" ]] && \
	BOOT_ID="$(awk -F, 'NR>1 {print $1+0}' "${REPO}/validation/fw-matrix.csv" | sort -n | tail -1)"

LOAD1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "")"
echo "phase6-chrono: run=${RUN_ID} resume=${RESUME_ISO} load1=${LOAD1} → ${RUN_DIR}"

for off in "${OFFSETS[@]}"; do
	# fractional sleep
	now="$(date +%s.%N 2>/dev/null || date +%s)"
	target="$(awk -v r="$RESUME_EPOCH" -v o="$off" 'BEGIN{printf "%.3f", r+o}')"
	wait_s="$(awk -v t="$target" -v n="$now" 'BEGIN{w=t-n; if(w<0)w=0; printf "%.3f", w}')"
	[[ "$(awk -v w="$wait_s" 'BEGIN{print (w>0)?1:0}')" -eq 1 ]] && sleep "$wait_s"

	off_ms="$(awk -v o="$off" 'BEGIN{printf "%d", o*1000}')"
	snap="$(vm_collect_snapshot "$off" "$RESUME_TS")"
	IFS=',' read -r _off pm a8 ab a721 fw8 fwb pw sink sp pb rt8 rtb rt721 audio result <<<"$snap"
	vm_dump_snapshot_verbose "$RUN_DIR" "${off_ms}" "$RESUME_TS"
	{
		printf '%s,' "$RUN_ID"
		printf '%s,' "$BOOT_ID"
		printf '%s,' "$PROC_BOOT_ID"
		printf '%s,' "$RESUME_ISO"
		printf '%s,' "$off"
		printf '%s,' "$off_ms"
		printf '%s,' "$pm"
		printf '%s,' "$a8"
		printf '%s,' "$ab"
		printf '%s,' "$a721"
		printf '%s,' "$fw8"
		printf '%s,' "$fwb"
		printf '%s,' "$pw"
		printf '%s,' "$sink"
		printf '%s,' "$sp"
		printf '%s,' "$pb"
		printf '%s,' "$rt8"
		printf '%s,' "$rtb"
		printf '%s,' "$rt721"
		printf '%s,' "$audio"
		printf '%s,' "$result"
		printf '%s\n' "${NOTES:-}"
	} >>"$CHRONO"
	echo "  t=${off}s (${off_ms}ms) composite=${result} pm=${pm} :8=${a8} fw=${fw8} sink=${sink}"
done

"${SCRIPT_DIR}/phase6-kmsg-parse.sh" "$RUN_ID" "$RESUME_TS"
"${SCRIPT_DIR}/phase6-resume-matrix-append.sh" \
	--run-id "$RUN_ID" \
	--boot-id "$BOOT_ID" \
	--resume-ts "$RESUME_ISO" \
	--chronology "$CHRONO" \
	--notes "${NOTES:-phase6-run-${RUN_ID}}" 2>/dev/null \
	|| "${SCRIPT_DIR}/phase5-resume-matrix-append.sh" \
		--run-id "$RUN_ID" --boot-id "$BOOT_ID" --resume-ts "$RESUME_ISO" \
		--timeline "$CHRONO" --notes "${NOTES:-phase6-run-${RUN_ID}}" || true

echo "load1=${LOAD1}" >>"${RUN_DIR}/meta.txt"
echo "phase6-chrono: done run=${RUN_ID}"
