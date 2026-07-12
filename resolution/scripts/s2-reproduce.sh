#!/usr/bin/env bash
# Try to reproduce S2 with repeated suspend cycles (witness gate calibration).
# Usage: sudo ./s2-reproduce.sh [max_attempts]
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${_SCRIPT_DIR}/../.." && pwd)}"
LIB="${REPO}/resolution/scripts/recovery/_lib.sh"
MAX="${1:-${PX13_S2_MAX_ATTEMPTS:-5}}"

# shellcheck source=/dev/null
source "$LIB"

export RESOLUTION_ASSUME_SUSPEND=1

echo "=== S2 REPRODUCTION (max ${MAX} attempts, min ${RESOLUTION_MIN_WITNESS:-W2}) ==="
echo "S2 = post-resume audio broken (what we fix). Kernel -110 upgrades to W3."

# Already broken post-suspend? Skip S0 gate and certify witness.
since="$(witness_journal_since "30 min ago")"
assess_witness_quality "$since"
if [[ "${RESOLUTION_WITNESS_VALID:-0}" == "1" ]] && post_resume_audio_broken; then
	echo "Already in S2 (${RESOLUTION_WITNESS_QUALITY}) — witness certified"
	"${REPO}/resolution/scripts/s2-oracle.sh" "$since"
	exit 0
fi

echo "Step 1: confirm S0"
if ! confirm_s0_health; then
	echo "S0 broken — running restore-boot-audio.sh ..."
	restore_rc=0
	"${REPO}/resolution/scripts/salvage/restore-boot-audio.sh" || restore_rc=$?
	[[ "$restore_rc" -eq 2 ]] && echo "restore: card up, playback still down" >&2
	[[ "$restore_rc" -gt 2 ]] && echo "restore failed (rc=${restore_rc})" >&2
	sleep 2
fi
if ! confirm_s0_health; then
	echo "S0 not healthy — fix boot audio first" >&2
	echo "  aplay -D hw:1,2 -f S16_LE -c 2 -r 48000 -t raw -d 1 /dev/zero" >&2
	echo "  reboot if both fail" >&2
	exit 1
fi

attempt=0
while [[ "$attempt" -lt "$MAX" ]]; do
	attempt=$((attempt + 1))
	echo ""
	echo "--- Attempt ${attempt}/${MAX}: suspend → settle → witness ---"
	sleep 3
	systemctl suspend
	wait_post_resume_settle

	since="$(witness_journal_since "3 min ago")"
	assess_witness_quality "$since"
	if [[ "${RESOLUTION_WITNESS_VALID:-0}" == "1" ]]; then
		echo ""
		"${REPO}/resolution/scripts/s2-oracle.sh" "$since"
		echo ""
		echo "S2 reproduced — run edge-cycle (audio broken post-resume is expected)"
		exit 0
	fi

	log "attempt ${attempt}: ${RESOLUTION_WITNESS_QUALITY} — ${RESOLUTION_WITNESS_REASON}"

	if [[ "$attempt" -lt "$MAX" ]]; then
		echo "Bug not reproduced (audio still OK) — another suspend in 10s..."
		sleep 10
		if ! confirm_s0_health; then
			prep_rc=0
			prepare_s0_for_retry || prep_rc=$?
			if [[ "$prep_rc" -eq 2 ]]; then
				"${REPO}/resolution/scripts/s2-oracle.sh" "$since"
				echo "S2 reproduced (detected on retry prep)"
				exit 0
			fi
			if [[ "$prep_rc" -eq 0 ]]; then
				log "transient playback glitch — continuing suspend loop"
				continue
			fi
			echo "Cannot continue — reboot and re-run" >&2
			exit 1
		fi
	fi
done

echo ""
echo "S2 not reproduced in ${MAX} attempts (audio still works after every suspend)"
since="$(witness_journal_since "5 min ago")"
"${REPO}/resolution/scripts/s2-oracle.sh" "$since" || true
exit 1
