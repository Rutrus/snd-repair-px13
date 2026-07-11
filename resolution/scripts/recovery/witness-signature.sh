#!/usr/bin/env bash
# Recovery Signature — S1..S5 checks. See resolution/EDGE-FRAMEWORK.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

FULL="${EDGE_FULL_SIGNATURE:-0}"
RESULT_FILE="${RESOLUTION_WITNESS_FILE:-}"

[[ "${1:-}" == "--full" ]] && FULL=1

log() { echo "[witness] $*" >&2; }

s1_rt721_ok() {
	local since
	since="$(witness_journal_since "2 min ago")"
	# No fresh -110 since last resume
	if journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -qE 'rt721.*(-110|wait_init_timeout|failed to resume)|wait_init_timeout|error -110'; then
		return 1
	fi
	if journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -qiE 'sdw.*attach|rt721.*probe|initialization_complete'; then
		return 0
	fi
	# SDW sysfs Attached
	local d
	for d in /sys/bus/soundwire/devices/*; do
		[[ -r "$d/status" ]] || continue
		grep -qi attached "$d/status" 2>/dev/null && return 0
	done
	# weak pass: no -110
	return 0
}

s2_alsa_card() {
	alsa_card_present
}

s3_userspace_sink() {
	local st
	st="$(userspace_sink_state)"
	[[ "$st" == ok ]] && return 0
	# Post-recovery: dummy-only or no sink = userspace still broken
	[[ "$st" == dummy || "$st" == none ]] && return 1
	# unknown: fall back to ALSA card
	s2_alsa_card
}

s4_playback() {
	witness_playback
}

s5_suspend2() {
	log "S5: suspend #2 (5s warning — Ctrl+C to skip)"
	sleep 5
	systemctl suspend
	sleep 3
	s4_playback
}

run_check() {
	local name="$1" fn="$2" out
	if "$fn"; then out=pass; else out=fail; fi
	printf '%s=%s\n' "$name" "$out"
	[[ "$out" == pass ]]
}

SIG_PASS=0
SIG_TOTAL=4
SIG_FULL=0

s1=fail s2=fail s3=fail s4=fail s5=skip

run_check S1 s1_rt721_ok && s1=pass || true
run_check S2 s2_alsa_card && s2=pass || true
run_check S3 s3_userspace_sink && s3=pass || true
run_check S4 s4_playback && s4=pass || true

SIG_PASS=0
[[ "$s1" == pass ]] && SIG_PASS=$((SIG_PASS + 1))
[[ "$s2" == pass ]] && SIG_PASS=$((SIG_PASS + 1))
[[ "$s3" == pass ]] && SIG_PASS=$((SIG_PASS + 1))
[[ "$s4" == pass ]] && SIG_PASS=$((SIG_PASS + 1))

if [[ "$FULL" == "1" && "$SIG_PASS" -eq 4 ]]; then
	SIG_TOTAL=5
	if s5_suspend2; then
		s5=pass
		SIG_PASS=5
		SIG_FULL=1
	else
		s5=fail
	fi
else
	s5=skip
	[[ "$SIG_PASS" -eq 4 ]] && SIG_FULL=0
fi

PARTIAL_OK=0
FULL_OK=0
[[ "$SIG_PASS" -ge 3 ]] && PARTIAL_OK=1
[[ "$SIG_PASS" -eq 4 && "$s5" == pass ]] && FULL_OK=1
[[ "$SIG_PASS" -eq 5 ]] && FULL_OK=1

export WITNESS_S1="$s1" WITNESS_S2="$s2" WITNESS_S3="$s3" WITNESS_S4="$s4" WITNESS_S5="$s5"
export WITNESS_SIG_PASS="$SIG_PASS" WITNESS_SIG_TOTAL="$SIG_TOTAL" WITNESS_FULL_OK="$FULL_OK"

if [[ -n "$RESULT_FILE" ]]; then
	cat >"$RESULT_FILE" <<EOF
s1=$s1
s2=$s2
s3=$s3
s4=$s4
s5=$s5
sig_pass=$SIG_PASS
sig_total=$SIG_TOTAL
full_ok=$FULL_OK
partial_ok=$PARTIAL_OK
EOF
fi

log "signature: $SIG_PASS/$SIG_TOTAL (S1=$s1 S2=$s2 S3=$s3 S4=$s4 S5=$s5)"

if [[ "$FULL_OK" -eq 1 ]]; then exit 0; fi
if [[ "$PARTIAL_OK" -eq 1 ]]; then exit 2; fi
exit 1
