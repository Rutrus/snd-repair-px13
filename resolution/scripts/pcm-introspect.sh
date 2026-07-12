#!/usr/bin/env bash
# PCM introspection — compare SmartAmp (pcm2) vs SimpleJack (pcm0) constraints.
# Answers: why does snd_pcm_hw_params() return EINVAL on hw:1,2 after resume?
#
# Usage:
#   sudo ./pcm-introspect.sh              # broken state (S2)
#   sudo ./pcm-introspect.sh --label S0   # tag output (run after clean boot for contrast)
#
# Compare two logs:
#   diff -u /var/log/snd-repair/pcm-intro-S0-*.log /var/log/snd-repair/pcm-intro-S2-*.log
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=recovery/_lib.sh
source "${_SCRIPT_DIR}/recovery/_lib.sh"

require_root "$0"

LABEL="S2"
SWEEP_ONLY=0
while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="${2:?}"; shift 2 ;;
	--sweep-only) SWEEP_ONLY=1; shift ;;
	-h | --help)
		echo "Usage: sudo $0 [--label S0|S2] [--sweep-only]"
		echo "  --sweep-only   PCM2 format/rate matrix only (quick)"
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
done

CARD="${PCM_INTROSPECT_CARD:-$(alsa_card_number 2>/dev/null || true)}"
[[ -n "$CARD" ]] || { echo "no amd-soundwire card" >&2; exit 1; }

LOG_DIR="${PCM_INTROSPECT_LOG_DIR:-/var/log/snd-repair}"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG="${LOG_DIR}/pcm-intro-${LABEL}-$(date +%Y%m%dT%H%M%S).log"

exec > >(tee -a "$LOG") 2>&1

section() { echo; echo "========== $* =========="; }

# Try aplay with explicit format — classify set_params vs other.
pcm2_try_config() {
	local dev="$1" fmt="$2" rate="$3" ch="$4"
	local err rc errfile
	errfile="$(mktemp)"
	timeout 4 aplay -D "$dev" -f "$fmt" -r "$rate" -c "$ch" -t raw -d 1 -q /dev/zero 2>"$errfile" || rc=$?
	rc="${rc:-0}"
	err="$(tr '\n' ' ' <"$errfile" | sed 's/  */ /g')"
	rm -f "$errfile"
	if [[ "$rc" -eq 0 ]]; then
		echo "PASS"
	elif echo "$err" | grep -qiE 'set_params|Imposible instalar|unable to install hw'; then
		echo "set_params_fail"
	elif echo "$err" | grep -qiE 'EINVAL|Argumento inválido|Invalid argument'; then
		echo "einval"
	elif echo "$err" | grep -qi busy; then
		echo "busy"
	else
		echo "fail(rc=${rc})"
	fi
}

pcm2_format_sweep() {
	local dev="hw:${CARD},2" fmt rate ch result
	echo "device=${dev}"
	printf '%-12s %-8s %-4s %-20s\n' FORMAT RATE CH RESULT
	for fmt in S16_LE S24_LE S32_LE FLOAT_LE; do
		for rate in 44100 48000; do
			for ch in 1 2; do
				result="$(pcm2_try_config "$dev" "$fmt" "$rate" "$ch")"
				printf '%-12s %-8s %-4s %-20s\n' "$fmt" "$rate" "$ch" "$result"
			done
		done
	done
	echo
	echo "If every cell is set_params_fail/einval → driver publishes no valid combo (DAPM/constraint)."
	echo "If only some fail → specific format/rate constraint regression after resume."
}

if [[ "$SWEEP_ONLY" == "1" ]]; then
	echo "=== PCM2 FORMAT SWEEP ==="
	echo "label: ${LABEL} time: $(date -Iseconds)"
	pcm2_format_sweep
	exit 0
fi

echo "=== PCM INTROSPECTION ==="
echo "label: ${LABEL}"
echo "time: $(date -Iseconds)"
echo "card: ${CARD}"
echo "log: ${LOG}"
echo "kernel: $(uname -r)"
echo

section "Witness snapshot"
echo "primary=$(witness_playback_alsa_hw_primary && echo pass || echo fail) class=${WITNESS_PCM_LAST_CLASS:-?}"
echo "any=$(witness_playback_alsa_hw && echo pass || echo fail)"
echo "sink=$(userspace_sink_presence_quality) default=$(userspace_default_sink_quality)"
echo

section "/proc/asound/cards + pcm"
cat /proc/asound/cards 2>/dev/null || true
echo
grep -E "^$(printf '%02d' "$CARD")-" /proc/asound/pcm 2>/dev/null || true
echo

section "aplay -l (card ${CARD})"
aplay -l 2>&1 | awk -v c="card ${CARD}:" '$0 ~ c {p=1} p {print} /^card / && $0 !~ c {p=0}' || true
echo

dump_hw_params() {
	local dev="$1"
	echo "--- aplay --dump-hw-params -D ${dev} ---"
	if aplay --dump-hw-params -D "$dev" /dev/zero 2>&1; then
		echo "result: dump_ok"
	else
		echo "result: dump_fail rc=$?"
	fi
	echo
}

section "HW params dump — PCM0 SimpleJack (hw:${CARD},0)"
dump_hw_params "hw:${CARD},0"

section "HW params dump — PCM2 SmartAmp (hw:${CARD},2)"
dump_hw_params "hw:${CARD},2"

section "PCM2 format/rate sweep (hw:${CARD},2)"
pcm2_format_sweep

section "PCM0 control sweep (hw:${CARD},0) — expect all PASS in S0"
dev0="hw:${CARD},0"
printf '%-12s %-8s %-4s %-20s\n' FORMAT RATE CH RESULT
for fmt in S16_LE S32_LE; do
	result="$(pcm2_try_config "$dev0" "$fmt" 48000 2)"
	printf '%-12s %-8s %-4s %-20s\n' "$fmt" 48000 2 "$result"
done
echo

section "aplay set_params probe (captured stderr)"
for pcm in 0 2; do
	dev="hw:${CARD},${pcm}"
	echo "--- ${dev} ---"
	if witness_pcm_try_aplay "$dev"; then
		echo "aplay: PASS"
	else
		echo "aplay: FAIL class=${WITNESS_PCM_LAST_CLASS} rc=${WITNESS_PCM_LAST_RC}"
		echo "stderr: ${WITNESS_PCM_LAST_ERR:-<empty>}"
	fi
	echo
done

section "sysfs PCM nodes"
for pcm in 0 2; do
	echo "--- pcm${pcm}p ---"
	witness_pcm_sysfs_dump "$CARD" "$pcm"
done

section "/proc/asound/card${CARD} (top-level)"
if [[ -d "/proc/asound/card${CARD}" ]]; then
	ls -la "/proc/asound/card${CARD}/" 2>/dev/null || true
	for f in /proc/asound/card${CARD}/*; do
		[[ -f "$f" ]] || continue
		base="$(basename "$f")"
		[[ "$base" == pcm* ]] && continue
		echo "--- ${f} ---"
		head -40 "$f" 2>/dev/null || echo "(unreadable)"
		echo
	done
else
	echo "(missing)"
fi

section "codec* under /proc/asound/card${CARD}"
for f in /proc/asound/card${CARD}/codec*; do
	[[ -e "$f" ]] || { echo "(no codec* files)"; break; }
	echo "--- $f ---"
	head -60 "$f" 2>/dev/null || true
	echo
done

_debugfs_asoc() {
	local root="$1"
	[[ -d "$root" ]] || return 1
	echo "--- ${root} (head) ---"
	find "$root" -maxdepth 2 -type f 2>/dev/null | head -30
	echo
	# Common DAPM / card state files
	for f in \
		"${root}/dapm" \
		"${root}/components" \
		"${root}/amd-soundwire" \
		"${root}/rt721" \
		"${root}/tas2783" \
		; do
		[[ -e "$f" ]] || continue
		echo "--- $f ---"
		head -80 "$f" 2>/dev/null || cat "$f" 2>/dev/null | head -80 || true
		echo
	done
}

section "debugfs asoc (if mounted)"
ASOC_DBG=""
for cand in /sys/kernel/debug/asoc /debug/asoc; do
	[[ -d "$cand" ]] && ASOC_DBG="$cand" && break
done
if [[ -n "$ASOC_DBG" ]]; then
	_debugfs_asoc "$ASOC_DBG"
else
	echo "not mounted — try: sudo mount -t debugfs debugfs /sys/kernel/debug"
fi

section "SoundWire + RT721 sysfs"
echo "RT721 attached: $(rt721_sysfs_attached && echo yes || echo no)"
ls -la /sys/bus/soundwire/devices/ 2>/dev/null | head -20 || true
for d in /sys/bus/soundwire/devices/*; do
	[[ -d "$d/driver" ]] || continue
	echo "--- $(basename "$d") driver=$(basename "$(readlink -f "$d/driver")") ---"
	[[ -f "$d/status" ]] && echo "status: $(cat "$d/status" 2>/dev/null)"
	[[ -f "$d/modalias" ]] && echo "modalias: $(cat "$d/modalias" 2>/dev/null)"
done
echo

section "dmesg tail (audio-related)"
dmesg 2>/dev/null | tail -80 | grep -Ei 'tas2783|rt721|dapm|soundwire|pcm|hw_params|multicodec|acp|snd_' || \
	echo "(no matching lines in last 80)"
echo

section "SUMMARY"
echo "label=${LABEL}"
for pcm in 0 2; do
	dev="hw:${CARD},${pcm}"
	witness_pcm_try_aplay "$dev" || true
	echo "hw:${CARD},${pcm}: ${WITNESS_PCM_LAST_CLASS} (rc=${WITNESS_PCM_LAST_RC})"
done
echo "log=${LOG}"
echo "==========================="
echo
echo "Next: reboot → run with --label S0 → suspend → run again --label S2 → diff logs"
