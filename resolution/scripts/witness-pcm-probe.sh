#!/usr/bin/env bash
# Characterize ALSA PCM state — set_params vs playback per device.
# Usage: sudo ./witness-pcm-probe.sh [card]
# Logs: /var/log/snd-repair/witness-pcm-*.log (optional WITNESS_PCM_LOG_DIR)
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=recovery/_lib.sh
source "${_SCRIPT_DIR}/recovery/_lib.sh"

require_root "$0"

CARD="${1:-$(alsa_card_number 2>/dev/null || true)}"
[[ -n "$CARD" ]] || { echo "no amd-soundwire card" >&2; exit 1; }

LOG_DIR="${WITNESS_PCM_LOG_DIR:-/var/log/snd-repair}"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG="${LOG_DIR}/witness-pcm-$(date +%Y%m%dT%H%M%S).log"

exec > >(tee -a "$LOG") 2>&1

echo "=== PCM PROBE ==="
echo "time: $(date -Iseconds)"
echo "card: ${CARD}"
echo "log: ${LOG}"
echo

echo "--- /proc/asound/pcm ---"
grep -E "^$(printf '%02d' "$CARD")-" /proc/asound/pcm 2>/dev/null || true
echo

echo "--- aplay -l (card ${CARD}) ---"
aplay -l 2>&1 | awk -v c="card ${CARD}:" '$0 ~ c {p=1} p {print} /^card / && $0 !~ c {p=0}' || true
echo

pcms="$(witness_pcm_list_playback "$CARD" || true)"
[[ -n "$pcms" ]] || pcms="0 2"

for pcm in $pcms; do
	dev="hw:${CARD},${pcm}"
	echo "========== ${dev} (pcm${pcm}p) =========="
	echo "--- sysfs (before open) ---"
	witness_pcm_sysfs_dump "$CARD" "$pcm"

	echo "--- aplay probe (S16_LE 48kHz 2ch) ---"
	if witness_pcm_try_aplay "$dev"; then
		echo "aplay: PASS (open+set_params+IO)"
	else
		echo "aplay: FAIL class=${WITNESS_PCM_LAST_CLASS} rc=${WITNESS_PCM_LAST_RC}"
		echo "stderr: ${WITNESS_PCM_LAST_ERR:-<empty>}"
	fi
	echo "--- sysfs after aplay (hw_params valid only if driver exposes) ---"
	witness_pcm_sysfs_dump "$CARD" "$pcm"
	echo

	echo "--- speaker-test probe (wav S16_LE 48kHz) ---"
	if witness_pcm_try_speaker_test "$dev"; then
		echo "speaker-test: PASS"
	else
		echo "speaker-test: FAIL class=${WITNESS_PCM_LAST_CLASS} rc=${WITNESS_PCM_LAST_RC}"
		echo "stderr: ${WITNESS_PCM_LAST_ERR:-<empty>}"
	fi
	echo
done

echo "--- userspace ---"
echo "sink=$(userspace_sink_presence_quality) default=$(userspace_default_sink_quality)"
echo "playback_strict=$(witness_playback && echo pass || echo fail)"
echo "primary=$(witness_playback_alsa_hw_primary && echo pass || echo fail)"
echo "any=$(witness_playback_alsa_hw && echo pass || echo fail)"
echo

echo "=== SUMMARY ==="
primary_dev="$(alsa_hw_dev 2>/dev/null || echo hw:?,?)"
witness_pcm_try_aplay "$primary_dev" || true
echo "primary ${primary_dev}: ${WITNESS_PCM_LAST_CLASS:-?} (rc=${WITNESS_PCM_LAST_RC:-?})"
for pcm in $pcms; do
	dev="hw:${CARD},${pcm}"
	witness_pcm_try_aplay "$dev" || true
	echo "hw:${CARD},${pcm}: ${WITNESS_PCM_LAST_CLASS} (rc=${WITNESS_PCM_LAST_RC})"
done
echo "==========================="
