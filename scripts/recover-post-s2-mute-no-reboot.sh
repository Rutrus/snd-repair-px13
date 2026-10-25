#!/usr/bin/env bash
# Recover Scenario-2 mute / stuck RT721 jack detect without reboot or PCI reset.
# Requires: sudo for SDW slave unbind/bind; user session for PipeWire.
#
# Usage:
#   sudo ./scripts/recover-post-s2-mute-no-reboot.sh
# Then (as desktop user): systemctl --user restart wireplumber pipewire pipewire-pulse
set -euo pipefail

TAS_DRV=/sys/bus/soundwire/drivers/slave-tas2783
RT_DRV=/sys/bus/soundwire/drivers/rt721-sdca
TAS=(sdw:0:1:0102:0000:01:8 sdw:0:1:0102:0000:01:b)
RT=sdw:0:1:025d:0721:01

if [[ ${EUID} -ne 0 ]]; then
	echo "Run as root (sudo). Refusing." >&2
	exit 1
fi

echo "Stop PipeWire in the user session first if PCM is busy, then re-run."
echo "=== unbind TAS ==="
for d in "${TAS[@]}"; do
	echo "$d" >"${TAS_DRV}/unbind" || echo "WARN: unbind $d failed"
done
sleep 1
echo "=== bind TAS ==="
for d in "${TAS[@]}"; do
	echo "$d" >"${TAS_DRV}/bind" || echo "WARN: bind $d failed"
done
sleep 1

echo "=== cycle rt721 (jack detect) ==="
echo "$RT" >"${RT_DRV}/unbind" || echo "WARN: rt721 unbind failed"
sleep 1
echo "$RT" >"${RT_DRV}/bind" || echo "WARN: rt721 bind failed"
sleep 2

echo "=== status ==="
for d in "${TAS[@]}" "$RT"; do
	st=$(cat "/sys/bus/soundwire/devices/$d/status" 2>/dev/null || echo '?')
	echo "$d $st"
done
if command -v amixer >/dev/null; then
	amixer -c 1 cget numid=15 2>/dev/null | grep -E 'name=|values=' || true
	amixer -c 1 cget numid=16 2>/dev/null | grep -E 'name=|values=' || true
fi

echo
echo "Done. As your desktop user:"
echo "  systemctl --user restart wireplumber pipewire pipewire-pulse"
echo "  wpctl set-default \$(wpctl status | sed -n 's/.* \\([0-9]*\\)\\. Audio Coprocessor Speaker.*/\\1/p' | head -1)"
echo "  pw-play /tmp/tone.wav   # or speaker-test -D pipewire -c 2 -t sine -f 440 -l 1"
echo "If headset is plugged: Headphone Jack / Headset Mic Jack should be 'on'; unplug/replug if still off."
