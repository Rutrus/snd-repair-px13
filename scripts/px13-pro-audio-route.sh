#!/usr/bin/env bash
# PX13 temporary routing while HiFi UCM is broken (no Headphone Jack / Switch).
# Use pro-audio endpoints by stable ALSA names (IDs change across WP restarts).
#
# Usage:
#   ./scripts/px13-pro-audio-route.sh jack-in    # headphones + headset mic
#   ./scripts/px13-pro-audio-route.sh jack-out   # speakers + digital mic
#   ./scripts/px13-pro-audio-route.sh status
set -euo pipefail

CARD=alsa_card.pci-0000_c4_00.5-platform-amd_sdw
SINK_HP=alsa_output.pci-0000_c4_00.5-platform-amd_sdw.pro-output-0
SINK_SPK=alsa_output.pci-0000_c4_00.5-platform-amd_sdw.pro-output-2
SRC_HS=alsa_input.pci-0000_c4_00.5-platform-amd_sdw.pro-input-1
SRC_DMIC=alsa_input.pci-0000_c4_00.5-platform-amd_sdw.pro-input-4
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber/default-nodes"

ensure_pro() {
	pactl set-card-profile "$CARD" pro-audio
	# Never leave stereo-fallback as preferred sink (zero capture ports).
	sleep 0.5
}

write_defaults() {
	local sink=$1 src=$2 sink_alt=$3 src_alt=$4
	mkdir -p "$(dirname "$STATE")"
	cat >"$STATE" <<EOF
[default-nodes]
default.configured.audio.sink=${sink}
default.configured.audio.sink.0=${sink_alt}
default.configured.audio.source=${src}
default.configured.audio.source.0=${src_alt}
EOF
}

cmd=${1:-status}
case "$cmd" in
jack-in)
	ensure_pro
	pactl set-default-sink "$SINK_HP"
	pactl set-sink-mute "$SINK_HP" 0
	pactl set-default-source "$SRC_HS"
	pactl set-source-mute "$SRC_HS" 0
	write_defaults "$SINK_HP" "$SRC_HS" "$SINK_SPK" "$SRC_DMIC"
	echo "jack-in: sink=Pro (HP) source=Pro1 (headset)"
	;;
jack-out)
	ensure_pro
	pactl set-default-sink "$SINK_SPK"
	pactl set-sink-mute "$SINK_SPK" 0
	pactl set-default-source "$SRC_DMIC"
	pactl set-source-mute "$SRC_DMIC" 0
	write_defaults "$SINK_SPK" "$SRC_DMIC" "$SINK_HP" "$SRC_HS"
	echo "jack-out: sink=Pro2 (speakers) source=Pro4 (DMIC)"
	;;
status)
	pactl list cards | awk "/${CARD#alsa_card.}/,/^Card #/" | grep -E 'Perfil activo|pro-audio|stereo' || true
	pactl info | grep -E 'Destino por defecto|Fuente por defecto'
	wpctl status 2>/dev/null | sed -n '/Audio/,/Video/p' || true
	;;
*)
	echo "Usage: $0 {jack-in|jack-out|status}" >&2
	exit 2
	;;
esac
