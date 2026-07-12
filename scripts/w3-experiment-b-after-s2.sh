#!/usr/bin/env bash
# W3 Experiment B — run after setting w3_dapm_sync_probe=1 BEFORE suspend.
#
# Usage:
#   echo 1 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe
#   systemctl suspend
#   ./scripts/w3-experiment-b-after-s2.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${REPO}/validation/w3-experiment-b-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

exec > >(tee "${OUT}/run.log") 2>&1

PROBE="$(cat /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe 2>/dev/null || echo missing)"
echo "=== W3 Experiment B (post-S2, dapm_sync) ==="
echo "time=$(date -Iseconds) w3_dapm_sync_probe=$PROBE"
echo

if [[ "$PROBE" != "Y" && "$PROBE" != "1" ]]; then
	echo "WARN: w3_dapm_sync_probe should be Y/1 before suspend for this experiment" >&2
fi

echo "=== Ear check: speaker-test pipewire ==="
timeout 8 speaker-test -D pipewire -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
	| tee "${OUT}/speaker-test-pw.log" || true
echo "(heard_tone: fill in ${OUT}/notes.txt)"
echo

journalctl -k -b 0 --no-pager 2>/dev/null \
	| awk '/PM: suspend exit/{flag=1} flag' \
	| grep 'W3 ctx=' | tee "${OUT}/w3-trace-post-s2.txt"

journalctl -k -b 0 --no-pager 2>/dev/null \
	| awk '/PM: suspend exit/{flag=1} flag' \
	| grep -E 'W3 ctx=dapm fn=sync|W3 ctx=fw fn=after_fw_reinit' \
	| tee "${OUT}/w3-sync-slice.txt"

cat >"${OUT}/notes.txt" <<EOF
W3 Experiment B — post-S2
time: $(date -Iseconds)
w3_dapm_sync_probe at collection: $PROBE
heard_tone: (yes/no)
EOF

echo "output: $OUT"
