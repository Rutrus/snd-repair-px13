#!/usr/bin/env bash
# Multi-client capture matrix — proves RW vs MMAP is driver-level, not arecord-specific.
#
# Usage (post-S2: resume first, then):
#   ./scripts/capture-client-access-matrix.sh
#   ./scripts/capture-client-access-matrix.sh --context cold
#   ./scripts/capture-client-access-matrix.sh --device hw:1,1 --format S16_LE
#
# Env:
#   MATRIX_RECORD_SEC=2
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ALSA_DEV="${MATRIX_ALSA_DEV:-hw:1,4}"
FMT="${MATRIX_FORMAT:-S32_LE}"
RECORD_SEC="${MATRIX_RECORD_SEC:-2}"
CONTEXT="${MATRIX_CONTEXT:-post-s2}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--device) ALSA_DEV="$2"; shift 2 ;;
	--format) FMT="$2"; shift 2 ;;
	--context) CONTEXT="$2"; shift 2 ;;
	--out-dir) OUT_DIR="$2"; shift 2 ;;
	-h|--help)
		sed -n '3,14p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS_FILE="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-${REPO}/validation/capture-client-matrix-${TS_FILE}}"
mkdir -p "$OUT_DIR"

exec > >(tee "${OUT_DIR}/matrix.log") 2>&1

echo "=== CAPTURE CLIENT × ACCESS MATRIX ==="
echo "time=$(date -Iseconds) context=$CONTEXT device=$ALSA_DEV format=$FMT sec=$RECORD_SEC"
echo "output_dir=$OUT_DIR"
echo "kernel=$(uname -r)"
echo

_min_bytes() {
	case "$FMT" in
	S32_LE) echo $((48000 * 4 * 2 * RECORD_SEC / 2)) ;;  # rough stereo floor
	*) echo $((48000 * 2 * 2 * RECORD_SEC / 4)) ;;
	esac
}
MIN_BYTES="$(_min_bytes)"

echo "--- stopping PipeWire ---"
systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
sleep 2

: > "${OUT_DIR}/results.tsv"
echo -e "id\tclient\taccess\tverdict\tbytes\tnote" >> "${OUT_DIR}/results.tsv"

_record_result() {
	local id="$1" client="$2" access="$3" verdict="$4" bytes="$5" note="${6:-}"
	printf '%s\n' "$id|$client|$access|$verdict|$bytes|$note" >> "${OUT_DIR}/results.tsv"
}

_run_probe() {
	local id="$1" client="$2" access="$3" note="$4"
	shift 4
	local wav="${OUT_DIR}/${id}.wav"
	local log="${OUT_DIR}/${id}.log"
	local rc=0 size=0 verdict=FAIL
	local timeout_sec=$((RECORD_SEC + 8))

	echo "--- $id: client=$client access=$access ---"
	if timeout "$timeout_sec" "$@" >"$log" 2>&1; then
		rc=0
	else
		rc=$?
		[[ "$rc" -eq 124 ]] && echo "TIMEOUT after ${timeout_sec}s" | tee -a "$log"
	fi
	size="$(stat -c%s "$wav" 2>/dev/null || echo 0)"
	if [[ "$rc" -eq 0 && "$size" -gt "$MIN_BYTES" ]]; then
		verdict=PASS
	elif [[ "$rc" -eq 124 && "$size" -gt "$MIN_BYTES" ]]; then
		verdict=PARTIAL
		echo "NOTE: timeout but captured $size bytes — pipeline did not EOS cleanly"
	fi
	echo "RESULT $id verdict=$verdict exit=$rc bytes=$size"
	tail -3 "$log" 2>/dev/null || true
	echo
	_record_result "$id" "$client" "$access" "$verdict" "$size" "$note"
}

# --- arecord (reference) ---
if command -v arecord >/dev/null; then
	_run_probe arecord-rw arecord RW "snd_pcm_readi / RW_INTERLEAVED" \
		arecord -D "$ALSA_DEV" -f "$FMT" -r 48000 -c 2 -d "$RECORD_SEC" \
		"${OUT_DIR}/arecord-rw.wav"
	_run_probe arecord-mmap arecord MMAP "snd_pcm_mmap_readi / MMAP_INTERLEAVED" \
		arecord -D "$ALSA_DEV" -f "$FMT" -r 48000 -c 2 -d "$RECORD_SEC" \
		-M --period-size=1024 --buffer-size=4096 "${OUT_DIR}/arecord-mmap.wav"
else
	echo "SKIP: arecord missing"
fi

# --- ffmpeg (always RW via libavdevice ALSA) ---
if command -v ffmpeg >/dev/null; then
	_run_probe ffmpeg-rw ffmpeg RW "libavdevice alsa input (RW)" \
		ffmpeg -y -hide_banner -loglevel error \
		-f alsa -ac 2 -ar 48000 -i "$ALSA_DEV" -t "$RECORD_SEC" \
		"${OUT_DIR}/ffmpeg-rw.wav"
else
	echo "SKIP: ffmpeg missing"
fi

# --- GStreamer alsasrc (RW) ---
if command -v gst-launch-1.0 >/dev/null; then
	_run_probe gstreamer-rw gstreamer RW "alsasrc default (RW)" \
		gst-launch-1.0 -e alsasrc device="$ALSA_DEV" num-buffers="$((48000 * RECORD_SEC))" ! \
		audio/x-raw,rate=48000,channels=2 ! wavenc ! \
		filesink location="${OUT_DIR}/gstreamer-rw.wav"
else
	echo "SKIP: gst-launch-1.0 missing"
fi

# --- sox (RW) ---
if command -v rec >/dev/null || command -v sox >/dev/null; then
	_run_probe sox-rw sox RW "sox rec (RW)" \
		rec -r 48000 -c 2 -b 16 -t alsa "$ALSA_DEV" \
		"${OUT_DIR}/sox-rw.wav" trim 0 "$RECORD_SEC"
else
	echo "SKIP: sox/rec not installed (optional: apt install sox)"
fi

# --- tinycap (MMAP on tinyalsa) ---
if command -v tinycap >/dev/null; then
	# tinycap: device card id, period count, period size, bits, channels
	local_card="${ALSA_DEV#hw:}"
	local_card="${local_card%%,*}"
	local_pcm="${ALSA_DEV##*,}"
	local_bits=32
	[[ "$FMT" == S16_LE ]] && local_bits=16
	_run_probe tinycap-mmap tinycap MMAP "tinyalsa mmap capture" \
		tinycap "${OUT_DIR}/tinycap-mmap.wav" -D "$local_card" -d "$local_pcm" \
		-c 2 -r 48000 -b "$local_bits" -p 1024 -n "$((RECORD_SEC * 48000 / 1024 + 1))"
else
	echo "SKIP: tinycap not installed (optional: tinyalsa-tools)"
fi

echo "--- restarting PipeWire ---"
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

{
	echo "# Client × access matrix"
	echo
	echo "**context:** $CONTEXT · **device:** $ALSA_DEV · **format:** $FMT"
	echo "**time:** $(date -Iseconds)"
	echo
	printf '| Client | Access | Verdict | Bytes | Note |\n'
	printf '|--------|--------|---------|-------|------|\n'
	tail -n +2 "${OUT_DIR}/results.tsv" | while IFS='|' read -r id client access verdict bytes note; do
		printf '| %s | %s | %s | %s | %s |\n' "$client" "$access" "$verdict" "$bytes" "$note"
	done
	echo
	rw_pass="$(grep '|RW|' "${OUT_DIR}/results.tsv" | grep -c '|PASS|' || true)"
	mmap_pass="$(grep '|MMAP|' "${OUT_DIR}/results.tsv" | grep -c '|PASS|' || true)"
	rw_total="$(grep '|RW|' "${OUT_DIR}/results.tsv" | wc -l | tr -d ' ')"
	mmap_total="$(grep '|MMAP|' "${OUT_DIR}/results.tsv" | wc -l | tr -d ' ')"
	echo "**rw_pass:** $rw_pass/$rw_total · **mmap_pass:** $mmap_pass/$mmap_total"
	echo
	if [[ "$rw_pass" -eq 0 && "$mmap_pass" -gt 0 && "$rw_total" -gt 0 ]]; then
		echo "→ All RW clients fail, all MMAP clients pass — **driver access mode**, not PipeWire or arecord."
	elif [[ "$rw_pass" -gt 0 ]]; then
		echo "→ At least one RW client passes — access mode alone may not explain failure in this context."
	else
		echo "→ Pattern inconclusive — see results.tsv"
	fi
} | tee "${OUT_DIR}/summary.md"

echo
echo "matrix complete: $OUT_DIR"
