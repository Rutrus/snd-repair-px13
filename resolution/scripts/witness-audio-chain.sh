#!/usr/bin/env bash
# Dump audio chain layers — kernel → ALSA hw/plughw → PipeWire → routing.
# Usage: sudo ./witness-audio-chain.sh
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=recovery/_lib.sh
source "${_SCRIPT_DIR}/recovery/_lib.sh"

require_root "$0"

layer_word() {
	[[ "$1" -eq 0 ]] && echo PASS || echo FAIL
}

echo "=== AUDIO CHAIN WITNESS ==="
echo "time: $(date -Iseconds)"
echo

echo "--- L1 Kernel (/proc/asound/cards) ---"
cat /proc/asound/cards 2>/dev/null || echo "(unavailable)"
L1=1
alsa_card_present && witness_aplay_list_ok && L1=0
echo "L1 verdict: $(layer_word "$L1")"
echo

echo "--- L1b /proc/asound/pcm ---"
cat /proc/asound/pcm 2>/dev/null || echo "(unavailable)"
echo

echo "--- L1c aplay -l ---"
aplay -l 2>&1 || true
echo

hw_dev="$(alsa_hw_dev 2>/dev/null || echo '?')"
plug_dev="$(alsa_plughw_dev 2>/dev/null || echo '?')"

echo "--- L2 ALSA primary ($(alsa_hw_dev 2>/dev/null || echo '?')) ---"
L2=1
witness_playback_alsa_hw_primary && L2=0
echo "L2 primary: $(layer_word "$L2") class=${WITNESS_PCM_LAST_CLASS:-?}"
[[ "$L2" -ne 0 && -n "${WITNESS_PCM_LAST_ERR:-}" ]] && echo "stderr: ${WITNESS_PCM_LAST_ERR}"
L2a=1
witness_playback_alsa_hw && L2a=0
echo "L2 any PCM: $(layer_word "$L2a")"
echo

card="$(alsa_card_number 2>/dev/null || true)"
if [[ -n "$card" ]]; then
	echo "--- L2d PCM sysfs (per device) ---"
	for pcm in $(witness_pcm_list_playback "$card" 2>/dev/null || echo "0 2"); do
		witness_pcm_sysfs_dump "$card" "$pcm"
	done
	if command -v amixer >/dev/null 2>&1; then
		echo "--- L2b amixer -c${card} scontrols ---"
		amixer -c "$card" scontrols 2>&1 | head -40 || true
		echo
		echo "--- L2c amixer -c${card} contents (head) ---"
		amixer -c "$card" contents 2>&1 | head -60 || true
		echo
	fi
fi

echo "--- L3 PipeWire sinks ---"
us_sink="$(userspace_sink_presence_quality)"
echo "sink presence: ${us_sink}"
L3=1
[[ "$us_sink" == real ]] && L3=0
echo "L3 verdict: $(layer_word "$L3")"
if [[ -x "${USERSPACE_WPCTL:-/usr/bin/wpctl}" ]]; then
	echo "--- wpctl status (Audio) ---"
	userspace_as_user "${USERSPACE_WPCTL:-/usr/bin/wpctl}" status 2>/dev/null \
		| awk '/^Audio$/,/^Video$/' || true
fi
if [[ -x "${USERSPACE_PACTL:-/usr/bin/pactl}" ]]; then
	echo "--- pactl list short sinks ---"
	userspace_as_user "${USERSPACE_PACTL:-/usr/bin/pactl}" list short sinks 2>/dev/null || true
fi
echo

echo "--- L4 Default sink ---"
us_default="$(userspace_default_sink_quality)"
echo "default sink: ${us_default}"
L4=1
[[ "$us_default" == real ]] && L4=0
echo "L4 verdict: $(layer_word "$L4")"
echo

echo "--- Driver gates (research) ---"
echo "RT721 sysfs: $(rt721_sysfs_attached && echo attached || echo missing)"
echo "journal -110: $(journal_rt721_timeout "$(witness_journal_since "5 min ago")" && echo present || echo clear)"
echo

echo "--- L5 Manual (not automated) ---"
echo "Listen: speaker-test -D ${hw_dev} -c2"
echo "        aplay -D ${hw_dev} /usr/share/sounds/alsa/Front_Center.wav"
echo "PCM probe: sudo resolution/scripts/witness-pcm-probe.sh"
echo

OVERALL=PASS
[[ "$L1" -eq 0 && "$L2" -eq 0 && "$L3" -eq 0 && "$L4" -eq 0 ]] || OVERALL=PARTIAL
[[ "$L1" -ne 0 || "$L2" -ne 0 ]] && OVERALL=FAIL

echo "=== SUMMARY ==="
echo "L1 kernel:     $(layer_word "$L1")"
echo "L2 primary:    $(layer_word "$L2") (${WITNESS_PCM_LAST_CLASS:-?})"
echo "L2 any PCM:    $(layer_word "$L2a")"
echo "L3 PipeWire:   $(layer_word "$L3") (${us_sink})"
echo "L4 default:    $(layer_word "$L4") (${us_default})"
echo "OVERALL:       ${OVERALL} (L5 audible = manual)"
echo "==========================="

case "$OVERALL" in
PASS) exit 0 ;;
PARTIAL | FALSE_PASS) exit 2 ;;
*) exit 1 ;;
esac
