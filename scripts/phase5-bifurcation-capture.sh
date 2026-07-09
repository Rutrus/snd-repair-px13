#!/usr/bin/env bash
# 60s "movie" after resume: sample bus + userspace at fixed offsets.
#
# Usually invoked by phase5-bifurcation-experiment.sh --arm (background worker).
# Manual (resume already happened):
#   ./scripts/phase5-bifurcation-capture.sh --from-last-resume [--notes N]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/validation-metrics.sh
. "${SCRIPT_DIR}/lib/validation-metrics.sh"

TIMELINE="${REPO}/validation/bifurcation-timeline.csv"
RUNS="${REPO}/validation/bifurcation-runs"
STATE_DIR="${REPO}/validation/.state"
OFFSETS=(0 2 5 10 20 30 60)
NOTES=""
FROM_LAST=0
WAIT_RESUME=0
ARM_EPOCH=""

usage() {
	sed -n '2,8p' "$0"
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--notes) NOTES="${2:-}"; shift 2 ;;
	--from-last-resume) FROM_LAST=1; shift ;;
	--wait-resume) WAIT_RESUME=1; ARM_EPOCH="${2:?epoch}"; shift 2 ;;
	-h|--help) usage ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

mkdir -p "$RUNS" "$STATE_DIR"

kmsg_resume_ts() {
	journalctl -k -b 0 --no-pager -g 'PM: suspend exit' 2>/dev/null | tail -1 \
		| awk '{print $1,$2,$3}'
}

wait_for_resume_after() {
	local arm="$1" ts line epoch
	while true; do
		line="$(journalctl -k -b 0 --no-pager -g 'PM: suspend exit' 2>/dev/null | tail -1 || true)"
		ts="$(echo "$line" | awk '{print $1,$2,$3}')"
		[[ -z "$ts" || "$ts" == "  " ]] && { sleep 1; continue; }
		epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
		if [[ "$epoch" -gt "$arm" ]]; then
			echo "$ts"
			return 0
		fi
		sleep 1
	done
}

next_run_id() {
	local f="$STATE_DIR/bifurcation-run-seq"
	local n=1
	[[ -f "$f" ]] && n=$(( $(cat "$f") + 1 ))
	echo "$n" >"$f"
	printf '%04d' "$n"
}

if [[ "$WAIT_RESUME" -eq 1 ]]; then
	echo "phase5-bif-capture: waiting for resume after arm epoch ${ARM_EPOCH}..."
	RESUME_TS="$(wait_for_resume_after "$ARM_EPOCH")"
else
	RESUME_TS="$(kmsg_resume_ts)"
	if [[ -z "$RESUME_TS" || "$RESUME_TS" == "  " ]]; then
		echo "No PM suspend exit this boot." >&2
		exit 1
	fi
	if [[ "$FROM_LAST" -eq 0 ]]; then
		echo "Use --from-last-resume or --wait-resume (via experiment --arm)." >&2
		exit 1
	fi
fi

RESUME_ISO="$(date -d "$RESUME_TS" -Is 2>/dev/null | cut -d+ -f1)"
RESUME_EPOCH="$(date -d "$RESUME_TS" +%s)"
PROC_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
RUN_ID="$(next_run_id)"
RUN_DIR="${RUNS}/run-${RUN_ID}"
mkdir -p "$RUN_DIR"

# boot_id from fw-matrix if present
BOOT_ID="?"
if [[ -f "${REPO}/validation/fw-matrix.csv" ]]; then
	BOOT_ID="$(awk -F, 'NR>1 {print $1+0}' "${REPO}/validation/fw-matrix.csv" | sort -n | tail -1)"
fi

if [[ ! -f "$TIMELINE" ]]; then
	echo "run_id,boot_id,proc_boot_id,resume_ts,offset_s,pm,uid8_attach,uidb_attach,rt721_attach,uid8_fw,uidb_fw,pipewire,default_sink,speaker_present,pb_without_fw,rt_status_8,rt_status_b,rt_status_rt721,audio_test,composite,notes" >"$TIMELINE"
fi

echo "phase5-bif-capture: run=${RUN_ID} resume=${RESUME_ISO} → ${RUN_DIR}"

for off in "${OFFSETS[@]}"; do
	target=$((RESUME_EPOCH + off))
	now="$(date +%s)"
	if [[ "$now" -lt "$target" ]]; then
		sleep $((target - now))
	fi
	snap="$(vm_collect_snapshot "$off" "$RESUME_TS")"
	IFS=',' read -r _off pm a8 ab a721 fw8 fwb pw sink sp pb rt8 rtb rt721 audio result <<<"$snap"
	vm_dump_snapshot_verbose "$RUN_DIR" "$off" "$RESUME_TS"
	{
		printf '%s,' "$RUN_ID"
		printf '%s,' "$BOOT_ID"
		printf '%s,' "$PROC_BOOT_ID"
		printf '%s,' "$RESUME_ISO"
		printf '%s,' "$off"
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
	} >>"$TIMELINE"
	echo "  t=${off}s composite=${result} pm=${pm} :8=${a8} fw=${fw8} sink=${sink} pw=${pw}"
done

# Final composite row → resume-matrix
"${SCRIPT_DIR}/phase5-resume-matrix-append.sh" \
	--run-id "$RUN_ID" \
	--boot-id "$BOOT_ID" \
	--resume-ts "$RESUME_ISO" \
	--timeline "$TIMELINE" \
	--notes "${NOTES:-bifurcation-run-${RUN_ID}}" \
	|| true

echo "phase5-bif-capture: done run=${RUN_ID} timeline→${TIMELINE}"
echo "  verbose dumps → ${RUN_DIR}/"
