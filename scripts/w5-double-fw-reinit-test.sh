#!/usr/bin/env bash
# W5 — double fw_reinit experiment (post-S2 silent, no re-suspend).
#
# Hypothesis A: second fw_reinit restores audio → bug is resume-path ordering
# Hypothesis B: still silent → first reset leaves chip in bad state regardless
#
# Prerequisites: W4b build, debugfs mounted, post-S2 speakers silent
#
# Usage:
#   sudo ./scripts/w5-double-fw-reinit-test.sh
#   sudo ./scripts/w5-double-fw-reinit-test.sh --no-play   # skip speaker-test
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
DO_PLAY=1

while [[ $# -gt 0 ]]; do
	case "$1" in
	--no-play) DO_PLAY=0; shift ;;
	-h|--help) sed -n '3,14p' "$0"; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date +%Y%m%d-%H%M%S)"
OUT="${REPO}/validation/w5-double-reinit-${TS}"
mkdir -p "$OUT"

exec > >(tee "${OUT}/run.log") 2>&1

echo "=== W5 double fw_reinit experiment ==="
echo "time=$(date -Iseconds)"

if [[ ! -d /sys/kernel/debug/tas2783 ]]; then
	echo "Mount debugfs and ensure W4b module loaded:"
	echo "  sudo mount -t debugfs none /sys/kernel/debug"
	exit 1
fi

echo
echo "==> Pre-trigger state"
journalctl -k -b 0 --no-pager | grep -E 'W5 ctx=|W2 ctx=tas fn=force_fw_reinit' | tail -5 || true

for uid in 8 11; do
	f="/sys/kernel/debug/tas2783/uid${uid}"
	if [[ ! -w "$f" ]]; then
		echo "Missing $f — rebuild with W4b and reboot" >&2
		exit 1
	fi
done

echo
echo "==> Trigger manual fw_reinit on uid8 + uid11"
echo 1 | tee /sys/kernel/debug/tas2783/uid8 >"${OUT}/trigger-uid8.txt"
echo 1 | tee /sys/kernel/debug/tas2783/uid11 >"${OUT}/trigger-uid11.txt"

sleep 2
journalctl -k -b 0 --no-pager | grep -E 'W5 ctx=|W4b ctx=write.*W5_MANUAL' >"${OUT}/w5-kernel.txt" || true

if [[ "$DO_PLAY" -eq 1 ]]; then
	echo
	echo "==> speaker-test hw:1,2 (confirm with your ears)"
	speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1 2>&1 | tee "${OUT}/speaker-test.txt" || true
fi

{
	echo "suspend_count=$(journalctl -k -b 0 --no-pager | grep -c 'PM: suspend entry' || true)"
	echo "result=USER_CONFIRM_REQUIRED"
} >"${OUT}/meta.txt"

cat <<EOF

==> W5 done. Snapshot: $OUT

Interpretation:
  - Audio after second reinit → resume-path ordering bug (W2 timing / DAPM vs init)
  - Still silent → hot-reset + init_seq insufficient (chip-private state)

Log: journalctl -k -b 0 | grep -E 'W5 ctx=|W4b ctx=write.*W5_MANUAL'
EOF
