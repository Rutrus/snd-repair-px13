#!/usr/bin/env bash
# Full edge cycle: confirm S0 → S2 → recovery → signature (optional S5).
# Usage: sudo ./edge-cycle.sh E09
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${_SCRIPT_DIR}/../.." && pwd)}"
INPUT="${1:-E09}"
FROM_S2=0
[[ "${2:-}" == "--from-s2" || "${RESOLUTION_FROM_S2:-0}" == "1" ]] && FROM_S2=1
RECOVERY_DIR="${REPO}/resolution/scripts/recovery"
LIB="${RECOVERY_DIR}/_lib.sh"

case "$INPUT" in
E09) RID=R09 ;;
E07) RID=R07 ;;
E08) RID=R08 ;;
E04) RID=R04 ;;
R*)  RID="$INPUT" ;;
*)   echo "unknown edge/recovery: $INPUT" >&2; exit 1 ;;
esac

# shellcheck source=/dev/null
source "$LIB"

echo "=== EDGE CYCLE: $INPUT ($RID) ==="

if [[ "$FROM_S2" == "1" ]]; then
	echo "Mode: --from-s2 (skip S0/suspend; already in S2)"
	export RESOLUTION_ASSUME_SUSPEND=1 RESOLUTION_WITNESS_VALID=1
	export RESOLUTION_WITNESS_QUALITY="${RESOLUTION_WITNESS_QUALITY:-W2}"
	export RESOLUTION_WITNESS_REASON="${RESOLUTION_WITNESS_REASON:-certified S2; recovery only}"
	echo "Step 1: recovery + signature"
	exec "${RECOVERY_DIR}/run-recovery.sh" "$RID"
fi

echo "Step 1: confirm S0 (ALSA direct — not PipeWire default)"
if ! confirm_s0_health; then
	echo "S0 not healthy — fix boot audio first" >&2
	echo "Hint: sudo PX13_ALSA_DEV=plughw:1,2 $0 $INPUT" >&2
	exit 1
fi

echo "Step 2: suspend #1 → post-resume settle"
sleep 3
systemctl suspend
wait_post_resume_settle

echo "Step 3: S2 witness oracle"
export RESOLUTION_ASSUME_SUSPEND=1
since="$(witness_journal_since "3 min ago")"
assess_witness_quality "$since"
echo "Witness: ${RESOLUTION_WITNESS_QUALITY} ($(witness_quality_label))"
if [[ "${RESOLUTION_WITNESS_VALID:-0}" == "1" ]]; then
	echo "Witness VALID — proceeding with recovery"
	export RESOLUTION_WITNESS_VALID RESOLUTION_WITNESS_QUALITY RESOLUTION_WITNESS_REASON
	echo "Step 4: recovery + signature"
	exec "${RECOVERY_DIR}/run-recovery.sh" "$RID"
fi

echo "Witness INVALID — ${RESOLUTION_WITNESS_REASON}"
echo "Step 4: skip recovery (NOT_EXECUTABLE)"
export RESOLUTION_WITNESS_VALID=0 RESOLUTION_WITNESS_QUALITY RESOLUTION_WITNESS_REASON
exec "${RECOVERY_DIR}/run-recovery.sh" "$RID" --not-executable
