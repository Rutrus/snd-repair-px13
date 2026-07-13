#!/usr/bin/env bash
# E2 — capture TAS2783 / card control surface for cold vs S2 diff.
#
# Usage:
#   ./scripts/tas2783-state-snapshot.sh --label pass-cold
#   ./scripts/tas2783-state-snapshot.sh --label fail-silent-s2
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
LABEL=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="$2"; shift 2 ;;
	-h|--help) sed -n '3,8p' "$0"; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date +%Y%m%d-%H%M%S)"
TAG="${LABEL:+$LABEL-}${TS}"
OUT="${REPO}/validation/tas2783-state-${TAG}"
mkdir -p "$OUT"

exec > >(tee "${OUT}/snapshot.log") 2>&1

echo "=== tas2783 state snapshot ==="
echo "time=$(date -Iseconds) label=${LABEL:-none}"
echo

{
	echo "kernel=$(uname -r)"
	echo "suspend_count=$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -c 'PM: suspend entry' || true)"
} >"${OUT}/meta.txt"

wpctl status 2>&1 | sed -n '/Audio/,/^Video/p' >"${OUT}/wpctl.txt"

amixer -c 1 scontents >"${OUT}/amixer-scontents.txt" 2>&1 || true
amixer -c 1 contents >"${OUT}/amixer-contents.txt" 2>&1 || true

# Jack / routing switches
{
	amixer -c 1 cget name='Headphone Jack' 2>&1 || true
	amixer -c 1 cget name='Headset Mic Jack' 2>&1 || true
	amixer -c 1 cget name='Headphone Switch' 2>&1 || true
	amixer -c 1 cget name='Left Spk Switch' 2>&1 || true
	amixer -c 1 cget name='Right Spk Switch' 2>&1 || true
	amixer -c 1 cget name='tas2783-1 Amp' 2>&1 || true
	amixer -c 1 cget name='tas2783-1 Speaker' 2>&1 || true
	amixer -c 1 cget name='tas2783-2 Amp' 2>&1 || true
	amixer -c 1 cget name='tas2783-2 Speaker' 2>&1 || true
} >"${OUT}/amixer-key-controls.txt" 2>&1

if command -v sudo >/dev/null 2>&1; then
	sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
fi

if [[ -r /sys/kernel/debug/asound/card1/dapm ]]; then
	cat /sys/kernel/debug/asound/card1/dapm >"${OUT}/dapm-full.txt"
	grep -iE 'tas2783|FU21|FU23|SPK|ASI|SmartAmp|multicodec|Headphone|Speaker' \
		"${OUT}/dapm-full.txt" >"${OUT}/dapm-filter.txt" || true
else
	echo "(debugfs dapm unavailable)" >"${OUT}/dapm-full.txt"
fi

cat /proc/asound/cards >"${OUT}/cards.txt" 2>&1
cat /proc/asound/pcm >"${OUT}/pcm.txt" 2>&1

for pcm in pcm0p pcm2p; do
	f="/proc/asound/card1/${pcm}/sub0/status"
	if [[ -r "$f" ]]; then
		cp "$f" "${OUT}/${pcm}-status.txt"
	fi
done

# SDW device sysfs (limited — no register dump without debug patches)
{
	echo "=== soundwire devices ==="
	ls -la /sys/bus/soundwire/devices/ 2>&1 || true
	for d in /sys/bus/soundwire/devices/sdw:0:1:0102:*; do
		[[ -d "$d" ]] || continue
		echo "--- $d ---"
		for f in modalias uevent; do
			[[ -r "$d/$f" ]] && cat "$d/$f" 2>/dev/null
		done
	done
} >"${OUT}/sdw-sysfs.txt" 2>&1

journalctl -k -b 0 --no-pager 2>/dev/null \
	| grep -iE 'tas2783|force_fw|fw_ready|without fw|W2 ctx' \
	| tail -40 >"${OUT}/kernel-tas-tail.txt" || true

echo "snapshot: $OUT"
echo "Compare: diff -ru validation/tas2783-state-pass-cold-* validation/tas2783-state-fail-silent-s2-*"
