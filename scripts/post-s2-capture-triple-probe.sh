#!/usr/bin/env bash
# Post-S2 capture triple probe — classify RT721 vs SDW capture vs DMIC only.
#
# Run after resume (Phase A, untouched). Playback should already PASS.
#
# Usage:
#   ./scripts/post-s2-capture-triple-probe.sh
#   ./scripts/post-s2-capture-triple-probe.sh --out-dir validation/capture-probe-TIMESTAMP
#
# Cases:
#   A — only hw:1,1 fails     → RT721 resume
#   B — hw:1,1 + 1,3 + 1,4 fail → SoundWire capture path
#   C — only hw:1,4 fails     → ACP DMIC only
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="${1:-${POST_S2_CAPTURE_PROBE_DIR:-${REPO}/validation/capture-probe-${TS}}}"

if [[ "${1:-}" == "--out-dir" ]]; then
	OUT="$2"
fi

mkdir -p "$OUT"
exec > >(tee "${OUT}/probe.log") 2>&1

echo "=== POST-S2 CAPTURE TRIPLE PROBE === time=$(date -Iseconds)"
echo "output_dir=$OUT"
echo

probe() {
	local dev="$1" fmt="$2" out="$3" label="$4"
	local log="${OUT}/arecord-${label}.log"
	local wav="${OUT}/${out}"
	local rc=0
	echo "--- arecord $dev ($label) fmt=$fmt ---"
	if arecord -D "$dev" -f "$fmt" -r 48000 -c 2 -d 3 "$wav" >"$log" 2>&1; then
		echo "RESULT $label=PASS size=$(stat -c%s "$wav" 2>/dev/null || echo '?')"
	else
		rc=1
		echo "RESULT $label=FAIL"
		tail -5 "$log" || true
	fi
	echo "$label $rc" >> "${OUT}/results.txt"
	return 0
}

: > "${OUT}/results.txt"

# Stop PipeWire if holding PCMs (optional — direct hw access)
if fuser /dev/snd/pcmC1D1c /dev/snd/pcmC1D3c /dev/snd/pcmC1D4c 2>/dev/null | grep -q .; then
	echo "NOTE: PipeWire may hold capture PCMs. For direct ALSA:"
	echo "  systemctl --user stop wireplumber pipewire pipewire-pulse"
	echo
fi

probe hw:1,1 S16_LE rt721.wav rt721
probe hw:1,3 S16_LE smartamp.wav smartamp
probe hw:1,4 S32_LE dmic.wav dmic

echo
echo "--- PCM status (post-probe) ---"
for pcm in /proc/asound/card1/pcm*c/sub0/status; do
	[[ -f "$pcm" ]] || continue
	echo "=== $pcm ==="
	cat "$pcm" 2>/dev/null || echo "(unavailable)"
done

echo
echo "--- kernel (last 1 min) ---"
journalctl -k --since "1 minute ago" --no-pager 2>/dev/null \
	| grep -iE 'sdw|rt721|tas2783|dmic|capture|prepare|deprepare|transport|error|fail|pcm' \
	| tail -40 || true

echo
echo "--- classification ---"
rt721=0 smartamp=0 dmic=0
grep -q '^rt721 0' "${OUT}/results.txt" && rt721=1 || true
grep -q '^smartamp 0' "${OUT}/results.txt" && smartamp=1 || true
grep -q '^dmic 0' "${OUT}/results.txt" && dmic=1 || true

if [[ "$rt721" -eq 1 && "$smartamp" -eq 1 && "$dmic" -eq 1 ]]; then
	echo "=> ALL PASS"
elif [[ "$rt721" -eq 0 && "$smartamp" -eq 1 && "$dmic" -eq 1 ]]; then
	echo "=> Case A: RT721 (hw:1,1) only — RT721 resume path"
elif [[ "$rt721" -eq 0 && "$smartamp" -eq 0 && "$dmic" -eq 0 ]]; then
	echo "=> Case B: all capture fail — SoundWire capture path"
elif [[ "$rt721" -eq 1 && "$smartamp" -eq 1 && "$dmic" -eq 0 ]]; then
	echo "=> Case C: DMIC (hw:1,4) only — ACP DMIC path"
else
	echo "=> Mixed — document matrix: rt721=$rt721 smartamp=$smartamp dmic=$dmic"
fi

echo
echo "probe complete: $OUT"
