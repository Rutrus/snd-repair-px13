#!/usr/bin/env bash
# Relative timeline anchored at amd manager_reset (journal wall clock).
#
# IMPORTANT — two clocks:
#   • journal t=+Nms  → ordering / short events only (ms resolution, can compress 5s waits)
#   • kernel t=+Nms   → driver-reported duration (use for wait_init_*, AMD t=+ since reset)
#
# Usage:
#   ./scripts/phase6-resume-timeline.sh [RUN_ID]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$REPO"
# shellcheck source=lib/phase6-journal.sh
. "${REPO}/scripts/lib/phase6-journal.sh"

RUN_ID="${1:-}"

lines() {
	if [[ -n "$RUN_ID" ]]; then
		phase6_lines_for_run "$RUN_ID" "resume_window"
	else
		phase6_lines_for_run "" "resume_window"
	fi
}

line_epoch_ms() {
	local line="$1" ts epoch ms
	ts="$(echo "$line" | awk '{print $1,$2,$3}')"
	epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
	ms="$(echo "$ts" | awk -F. '{print $2}' | head -c 3)"
	ms="${ms:-0}"
	echo $(( epoch * 1000 + 10#${ms} ))
}

kernel_t_ms() {
	local body="$1"
	echo "$body" | sed -n 's/.*t=+\([0-9]*\)ms.*/\1/p'
}

resume_id_from() {
	local body="$1"
	echo "$body" | sed -n 's/.*resume=\([0-9]*\).*/\1/p'
}

describe_amd_reset() {
	local body="$1"
	local link rid
	link="$(echo "$body" | sed -n 's/.*link=\([0-9]*\).*/\1/p')"
	rid="$(resume_id_from "$body")"
	echo "amd manager_reset link=${link:-?} resume=${rid:-?} (one call — clears all slaves)"
}

describe_bus_reset_dev() {
	local body="$1"
	local dev uid
	dev="$(echo "$body" | sed -n 's/.*dev=\([0-9]*\).*/\1/p')"
	uid="$(echo "$body" | sed -n 's/.*uid=0x\([0-9a-f]*\).*/\1/p')"
	echo "bus slave_detach dev=${dev} uid=0x${uid:-?} (trace of manager_reset, not a second reset)"
}

describe_line() {
	local body="$1"
	local rid kt

	if echo "$body" | grep -q 'ctx=amd fn=manager_reset'; then
		describe_amd_reset "$body"
	elif echo "$body" | grep -q 'fn=state_change.*reason=manager_reset'; then
		describe_bus_reset_dev "$body"
	elif echo "$body" | grep -q 'fn=ping_status'; then
		rid="$(resume_id_from "$body")"
		kt="$(kernel_t_ms "$body")"
		echo "amd ping_status resume=${rid:-?} kernel_t=+${kt:-?}ms $(echo "$body" | sed -n 's/.*resp=0x\([0-9a-f]*\).*/resp=0x\1/p')"
	elif echo "$body" | grep -q 'fn=queue_work'; then
		rid="$(resume_id_from "$body")"
		kt="$(kernel_t_ms "$body")"
		echo "amd queue_work resume=${rid:-?} kernel_t=+${kt:-?}ms $(echo "$body" | sed -n 's/.*devmask=0x\([0-9a-f]*\).*/devmask=0x\1/p')"
	elif echo "$body" | grep -q 'fn=handle_status'; then
		rid="$(resume_id_from "$body")"
		kt="$(kernel_t_ms "$body")"
		echo "amd handle_status resume=${rid:-?} kernel_t=+${kt:-?}ms $(echo "$body" | sed -n 's/.*st0=\([A-Z]*\).*st1=\([A-Z]*\).*st2=\([A-Z]*\).*st3=\([A-Z]*\).*/st0=\1 st1=\2 st2=\3 st3=\4/p')"
	elif echo "$body" | grep -q 'fn=state_change.*new=ATTACHED'; then
		echo "bus ATTACHED $(echo "$body" | sed -n 's/.*dev=\([0-9]*\).*uid=0x\([0-9a-f]*\).*/dev=\1 uid=0x\2/p')"
	elif echo "$body" | grep -q 'fn=completion'; then
		echo "bus completion $(echo "$body" | sed -n 's/.*dev=\([0-9]*\).*elapsed_ms=\(-*[0-9]*\).*/dev=\1 kernel_elapsed=\2ms/p')"
	elif echo "$body" | grep -q 'fn=wait_init_start'; then
		kt="$(kernel_t_ms "$body")"
		echo "rt721 wait_init_start  [kernel t=+${kt:-0}ms — use this clock for wait duration]"
	elif echo "$body" | grep -q 'fn=wait_init_ok'; then
		kt="$(kernel_t_ms "$body")"
		echo "rt721 wait_init_ok     [kernel t=+${kt:-?}ms]"
	elif echo "$body" | grep -q 'fn=wait_init_timeout'; then
		kt="$(kernel_t_ms "$body")"
		echo "rt721 wait_init_timeout [kernel t=+${kt:-?}ms — authoritative wait duration]"
	elif echo "$body" | grep -q 'fn=branch_fast_path'; then
		echo "rt721 branch_fast_path (runtime PM, resume=0)"
	elif echo "$body" | grep -q 'ctx=amd fn=resume_enter.*pm=system_resume'; then
		rid="$(resume_id_from "$body")"
		echo "amd system_resume_enter resume=${rid:-?}"
	elif echo "$body" | grep -q 'ctx=amd fn=resume_enter.*pm=runtime_resume'; then
		echo "amd runtime_resume_enter resume=0"
	elif echo "$body" | grep -q 'PM: suspend entry'; then
		echo "pm suspend_entry"
	elif echo "$body" | grep -q 'PM: suspend exit'; then
		echo "pm suspend_exit"
	else
		return 1
	fi
}

uses_kernel_clock_only() {
	local desc="$1"
	[[ "$desc" == rt721\ wait_init_* ]]
}

RAW="$(lines)"
[[ -n "$RAW" ]] || { echo "No PHASE6 lines in resume window." >&2; exit 1; }

ANCHOR_MS=""
SYSTEM_RID=""
while IFS= read -r line; do
	[[ -z "$line" ]] && continue
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //')"
	if echo "$body" | grep -q 'ctx=amd fn=manager_reset'; then
		ANCHOR_MS="$(line_epoch_ms "$line")"
		SYSTEM_RID="$(resume_id_from "$body")"
		break
	fi
done <<<"$RAW"

TITLE="Phase 6 resume timeline"
[[ -n "$RUN_ID" ]] && TITLE="${TITLE} (run ${RUN_ID})"
echo "=== ${TITLE} ==="
echo "  Clocks: journal t=+Nms (order only) | kernel t=+Nms (driver — use for waits & AMD since reset)"
if [[ -z "$ANCHOR_MS" ]]; then
	echo "  anchor: (no amd manager_reset found)"
else
	echo "  anchor: amd manager_reset = journal t+0 ms${SYSTEM_RID:+  resume=${SYSTEM_RID}}"
fi
echo ""

SEEN_BUS_DEVS=""
while IFS= read -r line; do
	[[ -z "$line" ]] && continue
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //')"
	desc="$(describe_line "$body" || true)"
	[[ -n "$desc" ]] || continue

	# Optional: only post-reset AMD with matching resume id when known
	if [[ -n "$SYSTEM_RID" && "$SYSTEM_RID" != "0" ]]; then
		rid="$(resume_id_from "$body")"
		if echo "$body" | grep -q 'ctx=amd fn=' && [[ -n "$rid" && "$rid" != "$SYSTEM_RID" && "$rid" != "0" ]]; then
			continue
		fi
	fi

	if uses_kernel_clock_only "$desc"; then
		echo "  ---  ${desc}"
	elif [[ -n "$ANCHOR_MS" ]]; then
		t=$(( $(line_epoch_ms "$line") - ANCHOR_MS ))
		printf "  t=%+5d ms  %s\n" "$t" "$desc"
	else
		echo "  ${desc}"
	fi
done <<<"$RAW"

# Level-1: log evidence only (does not prove code path absent)
if [[ -n "$ANCHOR_MS" ]]; then
	post="$(while IFS= read -r line; do
		body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //')"
		ms="$(line_epoch_ms "$line")"
		[[ "$ms" -ge "$ANCHOR_MS" ]] && echo "$body"
	done <<<"$RAW")"
	echo ""
	if ! echo "$post" | grep -q 'fn=ping_status'; then
		echo "  → Level-1: no ping_status **log** after amd manager_reset (resume=${SYSTEM_RID:-?})"
		echo "     Does not prove PING code absent — rebuild AMD trace, check resume= filter, or add pci-ps IRQ trace"
		if ! echo "$post" | grep -q 'fn=queue_work'; then
			echo "     Also: no queue_work / handle_status logs in same window"
		fi
	elif ! echo "$post" | grep -qE 'fn=queue_work.*devmask=0x[^0]'; then
		echo "  → Level-1: ping_status logged but devmask=0 or no queue_work (FAIL-B candidate)"
	elif ! echo "$post" | grep -q 'new=ATTACHED'; then
		echo "  → Level-1: queue_work with devmask but no bus ATTACHED log (FAIL-C candidate)"
	fi
fi

echo ""
echo "Compare PASS vs FAIL using kernel t=+ on wait_init_timeout and amd ping/queue lines."
