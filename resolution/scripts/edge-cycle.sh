#!/usr/bin/env bash
# Full edge cycle: confirm S0 → S2 → recovery → signature (optional S5).
# Usage: sudo ./edge-cycle.sh E09
#    or: sudo ./edge-cycle.sh R09
set -euo pipefail

REPO="${SND_REPAIR_REPO:-${HOME}/snd_repair}"
INPUT="${1:-E09}"
RECOVERY_DIR="${REPO}/resolution/scripts/recovery"

case "$INPUT" in
E09) RID=R09 ;;
E07) RID=R07 ;;
E08) RID=R08 ;;
E04) RID=R04 ;;
R*)  RID="$INPUT" ;;
*)   echo "unknown edge/recovery: $INPUT" >&2; exit 1 ;;
esac

echo "=== EDGE CYCLE: $INPUT ($RID) ==="
echo "Step 1: confirm S0 (speaker-test)"
if command -v speaker-test >/dev/null 2>&1; then
	speaker-test -c2 -t wav -l 1 || { echo "S0 not healthy — fix boot audio first" >&2; exit 1; }
fi

echo "Step 2: suspend #1 → expect S2 after resume (5s)"
sleep 3
systemctl suspend

echo "Step 3: confirm S2"
sleep 2
if command -v speaker-test >/dev/null 2>&1; then
	if speaker-test -c2 -t wav -l 1 >/dev/null 2>&1; then
		echo "WARNING: audio already OK — may be S0 not S2; continue anyway"
	fi
fi

echo "Step 4: recovery + signature"
exec "${RECOVERY_DIR}/run-recovery.sh" "$RID"
