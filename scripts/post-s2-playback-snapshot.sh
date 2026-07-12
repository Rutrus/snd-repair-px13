#!/usr/bin/env bash
# Capture playback-path state for PASS vs FAIL (silent) diff after S2.
#
# Run immediately after resume while testing audible output:
#   ./scripts/post-s2-playback-snapshot.sh
#   ./scripts/post-s2-playback-snapshot.sh --label pass-audible
#   ./scripts/post-s2-playback-snapshot.sh --label fail-silent
#
# Compare two dirs under validation/playback-snapshot-* with diff -ru.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LABEL=""
RECORD_SEC="${SNAPSHOT_RECORD_SEC:-3}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="$2"; shift 2 ;;
	-h|--help) sed -n '3,12p' "$0"; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date +%Y%m%d-%H%M%S)"
TAG="${LABEL:+$LABEL-}${TS}"
OUT="${REPO}/validation/playback-snapshot-${TAG}"
mkdir -p "$OUT"

exec > >(tee "${OUT}/snapshot.log") 2>&1

echo "=== post-S2 playback snapshot ==="
echo "time=$(date -Iseconds) label=${LABEL:-none} out=$OUT"
echo

{
	echo "kernel=$(uname -r)"
	echo "suspend_count=$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -c 'PM: suspend entry' || echo 0)"
	systemctl is-enabled px13-audio-resume.service 2>&1 || true
} >"${OUT}/meta.txt"

wpctl status 2>&1 | sed -n '/Audio/,/^Video/p' | tee "${OUT}/wpctl-status.txt" | head -40
echo

journalctl -k -b 0 --no-pager 2>/dev/null \
	| grep -E 'force_fw_reinit|fw_ready|without fw|playback without|fw download wait' \
	| tail -30 | tee "${OUT}/kernel-fw-tail.txt"
echo

{
	echo "=== amixer scontents (tas/spk/amp/mute) ==="
	amixer -c 1 scontents 2>&1 | grep -iE 'tas|spk|amp|mute|headphone|speaker|playback' || true
	echo
	echo "=== amixer contents (full) ==="
	amixer contents -c 1 2>&1 || true
} | tee "${OUT}/amixer-contents.txt"

_dapm_capture() {
	local out="$1"
	if [[ -r /sys/kernel/debug/asound/card1/dapm ]]; then
		cat /sys/kernel/debug/asound/card1/dapm >"$out" 2>/dev/null && return 0
	fi
	if command -v sudo >/dev/null 2>&1; then
		sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
		sudo cat /sys/kernel/debug/asound/card1/dapm 2>/dev/null >"$out" && return 0
	fi
	echo "(debugfs dapm unavailable — sudo mount -t debugfs none /sys/kernel/debug)" >"$out"
	return 1
}
_dapm_capture "${OUT}/dapm.txt"
grep -iE 'FU21|FU23|SPK|ASI|SmartAmp|multicodec| tas2783' "${OUT}/dapm.txt" 2>/dev/null \
	| tee "${OUT}/dapm-filter.txt" || true

cat /proc/asound/pcm 2>/dev/null | tee "${OUT}/proc-asound-pcm.txt"
echo

PCM="/proc/asound/card1/pcm2p/sub0"
echo "=== speaker-test pipewire (${RECORD_SEC}s) + pcm2p series ==="
timeout "$((RECORD_SEC + 4))" speaker-test -D pipewire -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
	>"${OUT}/speaker-test-pw.log" 2>&1 &
ST_PID=$!
sleep 1
for i in 0 1 2; do
	[[ -r "${PCM}/status" ]] && cp -f "${PCM}/status" "${OUT}/pcm2p-status-t${i}.txt" || echo closed >"${OUT}/pcm2p-status-t${i}.txt"
	[[ -r "${PCM}/hw_params" ]] && cp -f "${PCM}/hw_params" "${OUT}/pcm2p-hw_params-t${i}.txt" 2>/dev/null || true
	sleep 1
done
wait "$ST_PID" 2>/dev/null || true
grep -E '^(state|hw_ptr|appl_ptr|delay|avail)' "${OUT}"/pcm2p-status-t*.txt 2>/dev/null | tee "${OUT}/pcm2p-ptr-summary.txt" || true
echo

echo "=== speaker-test hw:1,2 (${RECORD_SEC}s) ==="
timeout "$((RECORD_SEC + 4))" speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
	>"${OUT}/speaker-test-hw.log" 2>&1 || true
tail -5 "${OUT}/speaker-test-hw.log" || true
echo

journalctl -k --since '3 min ago' --no-pager 2>/dev/null \
	| grep -iE 'tas2783|ASoC|dapm|ENZODBG|SDWCAP|error|ALERT' \
	| tail -40 | tee "${OUT}/kernel-playback-tail.txt"

echo
echo "snapshot complete: $OUT"
echo "Compare: diff -ru validation/playback-snapshot-<pass> validation/playback-snapshot-<fail>"
