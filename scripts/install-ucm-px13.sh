#!/usr/bin/env bash
# Install PX13 UCM overrides (internal DMIC + verify Speaker tas2783 hook).
#
# Usage:
#   sudo ./scripts/install-ucm-px13.sh
#   sudo ./scripts/install-ucm-px13.sh --dry-run
#
# After install (user session):
#   systemctl --user restart wireplumber pipewire
#   wpctl status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
UCM_ROOT="/usr/share/alsa/ucm2"
CARD_CONF="${UCM_ROOT}/conf.d/amd-soundwire/ASUSTeKCOMPUTERINC.-ProArtPX13HN7306EAC-1.0-HN7306EAC.conf"
DMIC_CONF="${UCM_ROOT}/sof-soundwire/acp-dmic.conf"
MARKER="# --- snd_repair: internal DMIC (acp-dmic) ---"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

run() {
	if [[ "$DRY" -eq 1 ]]; then
		echo "[dry-run] $*"
	else
		"$@"
	fi
}

if [[ "$(id -u)" -ne 0 ]] && [[ "$DRY" -eq 0 ]]; then
	echo "Run as root: sudo $0" >&2
	exit 1
fi

if [[ ! -f "$REPO/ucm2/sof-soundwire/acp-dmic.conf" ]]; then
	echo "Missing $REPO/ucm2/sof-soundwire/acp-dmic.conf" >&2
	exit 1
fi

if [[ ! -f "$CARD_CONF" ]]; then
	echo "Card UCM not found: $CARD_CONF" >&2
	echo "Install brainchillz stage 1 first (fix-px13-audio.sh)." >&2
	exit 1
fi

echo "==> Installing acp-dmic.conf"
run install -D -m 0644 "$REPO/ucm2/sof-soundwire/acp-dmic.conf" "$DMIC_CONF"

if grep -qF "$MARKER" "$CARD_CONF" 2>/dev/null; then
	echo "==> Machine conf already patched (MicCodec1)"
else
	echo "==> Patching machine UCM (Define.MicCodec1 acp-dmic)"
	if [[ "$DRY" -eq 1 ]]; then
		echo "[dry-run] append MicCodec1 block to $CARD_CONF"
	else
		cp -a "$CARD_CONF" "${CARD_CONF}.bak-snd-repair-dmic"
		cat >> "$CARD_CONF" <<EOF

${MARKER}
# Card components omit mic:dmic / cfg-mics — HiFi never included a Mic device.
# ALSA hw:\${CardId},4 works (acp-dmic-codec). Force-include local acp-dmic.conf.
Define.MicCodec1 "acp-dmic"
EOF
	fi
fi

if [[ "$DRY" -eq 0 ]]; then
	echo "==> Reload UCM"
	alsaucm -c 1 reload 2>/dev/null || true
fi

echo
echo "Done. User session:"
echo "  systemctl --user restart wireplumber pipewire"
echo "  alsaucm -c 1 set _verb HiFi && alsaucm -c 1 dump text | grep -A6 Device.Mic"
echo "  wpctl status   # expect Internal Microphone source"
