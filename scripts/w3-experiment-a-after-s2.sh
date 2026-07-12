#!/usr/bin/env bash
# W3 Experiment A — run immediately after S2 resume (w3_dapm_sync_probe=0).
#
# Prerequisite: pass-cold snapshot already taken on this boot.
#   ./scripts/post-s2-playback-snapshot.sh --label pass-cold
#
# Usage (after you wake from suspend):
#   ./scripts/w3-experiment-a-after-s2.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${REPO}/validation/w3-experiment-a-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

exec > >(tee "${OUT}/run.log") 2>&1

echo "=== W3 Experiment A (post-S2) ==="
echo "time=$(date -Iseconds)"
echo "w3_dapm_sync_probe=$(cat /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe 2>/dev/null || echo missing)"
echo

if [[ "$(cat /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe 2>/dev/null)" != "N" &&
      "$(cat /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe 2>/dev/null)" != "0" ]]; then
	echo "WARN: w3_dapm_sync_probe should be 0 for Experiment A" >&2
fi

echo "=== Ear check: speaker-test hw:1,2 (3s) ==="
timeout 8 speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
	| tee "${OUT}/speaker-test-hw.log" || true
echo "(Did you hear the tone? Note in ${OUT}/notes.txt)"
echo

echo "=== Playback snapshot (fail-silent label) ==="
"$SCRIPT_DIR/post-s2-playback-snapshot.sh" --label fail-silent 2>&1 | tee "${OUT}/snapshot-invoke.log"
LATEST="$(ls -td "${REPO}"/validation/playback-snapshot-fail-silent-* 2>/dev/null | head -1)"
echo "latest_snapshot=${LATEST:-none}"
echo

echo "=== W3 kernel trace (full boot) ==="
journalctl -k -b 0 --no-pager 2>/dev/null | grep 'W3 ctx=' | tee "${OUT}/w3-trace-full.txt"
echo

echo "=== W3 post-S2 slice (since last suspend) ==="
journalctl -k -b 0 --no-pager 2>/dev/null \
	| awk '/PM: suspend exit/{flag=1} flag' \
	| grep 'W3 ctx=' | tee "${OUT}/w3-trace-post-s2.txt"
echo

echo "=== W2 + fw ladder (post-S2 slice) ==="
journalctl -k -b 0 --no-pager 2>/dev/null \
	| awk '/PM: suspend exit/{flag=1} flag' \
	| grep -E 'W2 ctx=tas|force_fw_reinit|fw_ready|W3 ctx=fw' \
	| tee "${OUT}/w2-fw-post-s2.txt"
echo

cat >"${OUT}/notes.txt" <<EOF
W3 Experiment A — post-S2 collection
time: $(date -Iseconds)
heard_tone: (fill in: yes/no)
pass-cold baseline: validation/playback-snapshot-pass-cold-20260712-173934
compare: diff -ru validation/playback-snapshot-pass-cold-* validation/playback-snapshot-fail-silent-*

Key questions:
- W3 ctx=fw fn=fw_reinit after S2? (tas_io_init only)
- W3 ctx=dapm tag=post-fw_reinit widget=FU21/FU23 power/active?
- W3 ctx=dapm fn=fu21_event event=2 (POST_PMU) on first playback after S2?
EOF

echo "=== Done ==="
echo "output: $OUT"
echo "Fill heard_tone in: ${OUT}/notes.txt"
