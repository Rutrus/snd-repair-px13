#!/usr/bin/env bash
# Recover asymmetric Scenario-2 mute (often right TAS amp silent while left works).
# Re-arms 0001b via a short s2idle — does NOT PCI-reset and does NOT SDW-rebind
# (rebind can break HiFi Jack controls).
#
# Usage:
#   ./scripts/recover-asymmetric-amp-mute.sh          # 5s sleep
#   ./scripts/recover-asymmetric-amp-mute.sh 8        # N seconds
set -euo pipefail

SECS=${1:-5}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}

SINK=alsa_output.pci-0000_c4_00.5-platform-amd_sdw.HiFi__Speaker__sink

echo "==> Stopping PipeWire (clean reopen after wake)"
systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true

echo "==> s2idle ${SECS}s via rtcwake (sudo) — expect 0001b on both TAS"
sudo rtcwake -m mem -s "$SECS"

echo "==> Restarting PipeWire"
systemctl --user start pipewire wireplumber pipewire-pulse
sleep 2
pactl set-card-profile alsa_card.pci-0000_c4_00.5-platform-amd_sdw HiFi 2>/dev/null || true
pactl set-default-sink "$SINK" 2>/dev/null || true
pactl set-sink-volume "$SINK" 100% 100% 2>/dev/null || true

echo "==> Markers (expect post-resume fw_reinit ×2)"
journalctl -k --since "30 sec ago" --no-pager | grep -E 'resume enum kick|post-resume fw_reinit' || true

echo
echo "Test right channel:  pw-play /tmp/tone-R.wav"
echo "Or: speaker-test -D pipewire -c 2 -t sine -f 500 -l 1"
