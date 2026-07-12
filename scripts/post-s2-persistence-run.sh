#!/usr/bin/env bash
# KPI-U persistence gate — repeated S2 cycles with user-path witness (PipeWire intact).
#
# Usage:
#   ./scripts/post-s2-persistence-run.sh 3
#   ./scripts/post-s2-persistence-run.sh 10
#
# Preconditions: px13 disabled (optional), W1+W2, user session with PipeWire.
# Env: POST_S2_SETTLE_SEC=45
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CYCLES="${1:-3}"
SETTLE_SEC="${POST_S2_SETTLE_SEC:-45}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
SUMMARY="${REPO}/validation/post-s2-persistence-kpi-u-${RUN_ID}.csv"
MASTER_LOG="${REPO}/validation/post-s2-persistence-kpi-u-${RUN_ID}.log"

if ! [[ "$CYCLES" =~ ^[0-9]+$ ]] || [[ "$CYCLES" -lt 1 ]]; then
	echo "Usage: $0 <cycles>" >&2
	exit 1
fi

exec > >(tee "$MASTER_LOG") 2>&1

echo "=== KPI-U S2 persistence run ==="
echo "cycles=$CYCLES settle_sec=$SETTLE_SEC run_id=$RUN_ID"
echo "px13: $(systemctl is-enabled px13-audio-resume.service 2>&1 || echo '?')"
echo "summary=$SUMMARY"
echo

echo "cycle,time,kpi_u,internal_mic,headset_mic,playback,witness_dir" > "$SUMMARY"

fail=0
for ((n = 1; n <= CYCLES; n++)); do
	echo "--- cycle $n/$CYCLES: systemctl suspend ---"
	systemctl suspend || true
	echo "waiting ${SETTLE_SEC}s post-resume (do NOT restart PipeWire)..."
	sleep "$SETTLE_SEC"

	WITNESS_OUT="${REPO}/validation/post-s2-user-witness/persist-${RUN_ID}-cycle${n}"
	if ! "$SCRIPT_DIR/post-s2-user-witness.sh" --out-dir "$WITNESS_OUT"; then
		kpi_u=FAIL
		fail=1
	else
		kpi_u=PASS
	fi

	int= hs= pb= t=
	if [[ -f "${WITNESS_OUT}/kpi-u.txt" ]]; then
		# shellcheck source=/dev/null
		eval "$(grep -E '^time=|^internal_mic_record=|^headset_mic_record=|^playback=' \
			"${WITNESS_OUT}/kpi-u.txt" | sed 's/^/export /')"
		int=$internal_mic_record
		hs=$headset_mic_record
		pb=$playback
		t=$time
	fi
	echo "cycle $n: kpi_u=$kpi_u int=$int hs=$hs pb=$pb"
	echo "$n,$t,$kpi_u,$int,$hs,$pb,$WITNESS_OUT" >> "$SUMMARY"

	if [[ "$kpi_u" != PASS ]]; then
		echo "FAIL KPI-U at cycle $n — stopping persistence run" >&2
		break
	fi
done

echo
if [[ "$fail" -eq 0 ]]; then
	echo "=> KPI-U persistence PASS ($CYCLES/$CYCLES cycles)"
	echo "kpi_u_persistence=PASS cycles=$CYCLES" > "${REPO}/validation/post-s2-persistence-kpi-u-${RUN_ID}.result"
	exit 0
fi

echo "=> KPI-U persistence FAIL (see $SUMMARY)"
echo "kpi_u_persistence=FAIL" > "${REPO}/validation/post-s2-persistence-kpi-u-${RUN_ID}.result"
exit 1
