#!/usr/bin/env bash
# W5 reproducibility — N full S2 cycles: silent after W2 → manual reinit → audio?
#
# Priority experiment before W6 delay sweep. Proves whether userspace 2nd
# fw_reinit consistently restores audible playback.
#
# Usage:
#   sudo ./scripts/w5-reproducibility-test.sh
#   sudo ./scripts/w5-reproducibility-test.sh --cycles 5
#   sudo ./scripts/w5-reproducibility-test.sh --cycles 3 --no-pre-play
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CYCLES=5
DO_PRE_PLAY=1
SUSPEND_SLEEP=20
W5_WAIT=2

usage() {
	sed -n '3,18p' "$0"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--cycles) CYCLES="${2:-5}"; shift 2 ;;
	--no-pre-play) DO_PRE_PLAY=0; shift ;;
	--suspend-sleep) SUSPEND_SLEEP="${2:-20}"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown: $1" >&2; usage >&2; exit 1 ;;
	esac
done

if [[ $EUID -ne 0 ]]; then
	echo "Run as root (needs suspend + debugfs write)" >&2
	exit 1
fi

mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
for uid in 8 11; do
	[[ -w "/sys/kernel/debug/tas2783/uid${uid}" ]] || {
		echo "Missing debugfs uid${uid} — rebuild W4b+ and reboot" >&2
		exit 1
	}
done

TS="$(date +%Y%m%d-%H%M%S)"
OUT="${REPO}/validation/w5-repro-${TS}"
mkdir -p "$OUT"

exec > >(tee "${OUT}/run.log") 2>&1

echo "=== W5 reproducibility test ==="
echo "time=$(date -Iseconds) cycles=$CYCLES"

pass=0
fail=0
skip=0

for ((i = 1; i <= CYCLES; i++)); do
	cdir="${OUT}/cycle-${i}"
	mkdir -p "$cdir"
	echo
	echo "========== Cycle $i / $CYCLES =========="

	echo "==> S2 suspend (${SUSPEND_SLEEP}s wake margin)"
	systemctl suspend || true
	sleep "$SUSPEND_SLEEP"

	journalctl -k -b 0 --no-pager | grep -E 'W2 ctx=tas|W7 ctx=ts.*w2_' \
		>"${cdir}/w2-kernel.txt" || true

	if [[ "$DO_PRE_PLAY" -eq 1 ]]; then
		echo "==> Pre-W5 speaker-test (expect silence — control)"
		speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1 \
			2>&1 | tee "${cdir}/speaker-pre-w5.txt" || true
	fi

	echo "==> W5 manual fw_reinit uid8 + uid11"
	echo 1 | tee /sys/kernel/debug/tas2783/uid8 >"${cdir}/trigger-uid8.txt"
	echo 1 | tee /sys/kernel/debug/tas2783/uid11 >"${cdir}/trigger-uid11.txt"
	sleep "$W5_WAIT"

	journalctl -k -b 0 --no-pager | grep -E 'W5 ctx=|W7 ctx=ts.*w5_' \
		>"${cdir}/w5-kernel.txt" || true

	echo "==> Post-W5 speaker-test — listen for 440 Hz"
	speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1 \
		2>&1 | tee "${cdir}/speaker-post-w5.txt" || true

	if [[ -t 0 ]]; then
		read -r -p "Cycle $i: did you HEAR the tone? [y/N/s=skip] " ans || ans=n
	else
		ans=s
		echo "Non-interactive — mark audio in ${cdir}/meta.txt"
	fi

	case "${ans,,}" in
	y|yes) audio=PASS; pass=$((pass + 1)) ;;
	s|skip) audio=SKIP; skip=$((skip + 1)) ;;
	*) audio=FAIL; fail=$((fail + 1)) ;;
	esac

	{
		echo "cycle=$i"
		echo "audio=$audio"
		echo "suspend_count=$(journalctl -k -b 0 --no-pager | grep -c 'PM: suspend entry' || true)"
	} >"${cdir}/meta.txt"
	echo "cycle $i → $audio"
done

{
	echo "cycles=$CYCLES"
	echo "pass=$pass"
	echo "fail=$fail"
	echo "skip=$skip"
	if [[ $fail -eq 0 && $pass -gt 0 && $skip -eq 0 ]]; then
		echo "summary=REPRODUCIBLE"
	elif [[ $pass -gt 0 && $fail -gt 0 ]]; then
		echo "summary=INTERMITTENT"
	else
		echo "summary=NOT_REPRODUCIBLE"
	fi
} >"${OUT}/summary.txt"

if command -v "${SCRIPT_DIR}/w7-ts-capture.sh" >/dev/null 2>&1; then
	"${SCRIPT_DIR}/w7-ts-capture.sh" --last-s2 >"${OUT}/w7-timeline-last-boot.txt" 2>/dev/null || true
fi

cat <<EOF

==> W5 reproducibility done: $OUT
pass=$pass fail=$fail skip=$skip

Interpretation:
  pass=$CYCLES fail=0  → solid fact: userspace 2nd fw_reinit always restores audio
  mixed pass/fail       → intermittent; collect W7 timeline per cycle
  pass=0                → W5 no longer holds; revisit stack state

Next (only if reproducible):
  sudo ./scripts/w6-minimal-sweep.sh
EOF
