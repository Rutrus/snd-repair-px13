#!/usr/bin/env bash
# Diff PipeWire capture path (KPI-U) vs direct ALSA (KPI-K) on the same PCM.
#
# Case A: pw-record with PipeWire running (typically pcm4c = Internal Mic / DMIC)
# Case B: arecord -D hw:1,4 after stopping PipeWire
#
# Usage:
#   ./scripts/post-s2-pw-vs-alsa-diff.sh
#   ./scripts/post-s2-pw-vs-alsa-diff.sh --device hw:1,1 --pcm pcm1c   # RT721
#
# Env:
#   DIFF_RECORD_SEC=4
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ALSA_DEV="${DIFF_ALSA_DEV:-hw:1,4}"
PCM_PROC="${DIFF_PCM_PROC:-/proc/asound/card1/pcm4c/sub0}"
RECORD_SEC="${DIFF_RECORD_SEC:-4}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--device) ALSA_DEV="$2"; shift 2 ;;
	--pcm) PCM_PROC="$2"; shift 2 ;;
	--out-dir) OUT_DIR="$2"; shift 2 ;;
	-h|--help)
		sed -n '3,14p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date -Iseconds)"
TS_FILE="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-${REPO}/validation/pw-vs-alsa-diff-${TS_FILE}}"
mkdir -p "$OUT_DIR"/{case-a-pw,case-b-alsa,before}

exec > >(tee "${OUT_DIR}/diff.log") 2>&1

echo "=== PW vs ALSA CAPTURE DIFF ==="
echo "time=$TS alsa_dev=$ALSA_DEV pcm_proc=$PCM_PROC"
echo "output_dir=$OUT_DIR"
echo

need() { command -v "$1" >/dev/null || { echo "FAIL: need $1"; exit 1; }; }
need wpctl
need pw-record
need arecord

_default_source_id() {
	wpctl status 2>/dev/null | awk '
		/^Audio/ { in_audio=1 }
		in_audio && /Sources:/ { in_src=1; next }
		in_src && /^(Settings|Video|$)/ { exit }
		in_src && /\*/ && /Microphone/ {
			if (match($0, /\*[[:space:]]+([0-9]+)/, a)) { print a[1]; exit }
		}
	'
}

_snap() {
	local dir="$1" label="$2"
	local base="${dir}/${label}"
	mkdir -p "$dir"
	[[ -r "${PCM_PROC}/status" ]] && cp -f "${PCM_PROC}/status" "${base}-status.txt" 2>/dev/null || echo closed >"${base}-status.txt"
	[[ -r "${PCM_PROC}/hw_params" ]] && cp -f "${PCM_PROC}/hw_params" "${base}-hw_params.txt" 2>/dev/null || echo closed >"${base}-hw_params.txt"
	[[ -r "${PCM_PROC}/sw_params" ]] && cp -f "${PCM_PROC}/sw_params" "${base}-sw_params.txt" 2>/dev/null || echo closed >"${base}-sw_params.txt"
	[[ -r "${PCM_PROC}/info" ]] && cp -f "${PCM_PROC}/info" "${base}-info.txt" 2>/dev/null || true
}

_snap_series() {
	local dir="$1" prefix="$2" n="$3" interval="$4"
	local i=0
	while [[ "$i" -lt "$n" ]]; do
		_snap "$dir" "${prefix}-t${i}"
		sleep "$interval"
		i=$((i + 1))
	done
}

_ucm_dump() {
	local out="$1"
	local card
	card="$(awk '/ProArtPX13|amdsoundwire/ {print $1; exit}' /proc/asound/cards 2>/dev/null || true)"
	{
		echo "card_id=$card"
		alsaucm listcards 2>&1 || true
		if [[ -n "$card" ]]; then
			alsaucm -c "$card" list _devices 2>&1 || true
			alsaucm -c "$card" dump text 2>&1 || alsaucm -c "$card" dump 2>&1 || true
		fi
	} >"$out"
}

_controls_dump() {
	local out="$1"
	{
		echo "=== amixer -c 1 ==="
		amixer -c 1 2>&1 || true
		echo
		echo "=== amixer contents -c 1 (head) ==="
		amixer contents -c 1 2>&1 | head -80 || true
	} >"$out"
}

_fuser_dump() {
	local out="$1"
	fuser -v /dev/snd/* 2>&1 >"$out" || true
}

_wpctl_inspect() {
	local id="$1" out="$2"
	wpctl inspect "$id" 2>&1 | tee "$out" || true
}

echo "--- baseline (PipeWire running) ---"
wpctl status 2>&1 | tee "${OUT_DIR}/before/wpctl-status.txt" | sed -n '/Audio/,/^Video/p' | head -35
echo

SRC_ID="$(_default_source_id || true)"
echo "default_source_id=${SRC_ID:-none}"
_wpctl_inspect "${SRC_ID:-0}" "${OUT_DIR}/before/wpctl-inspect-default-source.txt"
_ucm_dump "${OUT_DIR}/before/ucm-dump.txt"
_controls_dump "${OUT_DIR}/before/controls.txt"
_fuser_dump "${OUT_DIR}/before/fuser-snd.txt"
cat /proc/asound/pcm 2>/dev/null | tee "${OUT_DIR}/before/proc-asound-pcm.txt"
echo

# ── Case A: PipeWire path ─────────────────────────────────────────────
echo "=== CASE A: pw-record (${RECORD_SEC}s, PipeWire running) ==="
CA="${OUT_DIR}/case-a-pw"
_snap "${CA}" "pre-open"
if [[ -n "$SRC_ID" ]]; then
	pw-record --target="$SRC_ID" "${CA}/capture.wav" >"${CA}/pw-record.log" 2>&1 &
	PW_PID=$!
	sleep 1
	_snap "${CA}" "during-open"
	_snap_series "${CA}" "during" 3 1
	sleep $((RECORD_SEC - 4))
	[[ $((RECORD_SEC - 4)) -lt 0 ]] && sleep "$RECORD_SEC"
	kill -INT "$PW_PID" 2>/dev/null || true
	wait "$PW_PID" 2>/dev/null || true
	_snap "${CA}" "post-close"
	ls -la "${CA}/capture.wav" 2>/dev/null || true
	file "${CA}/capture.wav" 2>/dev/null || true
else
	echo "SKIP: no default source"
fi
_wpctl_inspect "${SRC_ID:-0}" "${CA}/wpctl-inspect-after.txt"
_fuser_dump "${CA}/fuser-snd-after.txt"
echo

# ── Case B: direct ALSA (stop PW) ───────────────────────────────────
echo "=== CASE B: arecord $ALSA_DEV (PipeWire stopped) ==="
CB="${OUT_DIR}/case-b-alsa"
echo "stopping PipeWire..."
systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
sleep 2
_snap "${CB}" "pre-open"
_ucm_dump "${CB}/ucm-dump-pre.txt"
_controls_dump "${CB}/controls-pre.txt"

if arecord -D "$ALSA_DEV" -f S32_LE -r 48000 -c 2 -d "$RECORD_SEC" \
	"${CB}/capture.wav" >"${CB}/arecord.log" 2>&1 &
then
	AR_PID=$!
	sleep 1
	_snap "${CB}" "during-open"
	_snap_series "${CB}" "during" 3 1
	wait "$AR_PID" 2>/dev/null || true
else
	echo "arecord failed to start"
fi
_snap "${CB}" "post-close"
ls -la "${CB}/capture.wav" 2>/dev/null || true
tail -8 "${CB}/arecord.log" 2>/dev/null || true
journalctl -k --since "2 minutes ago" --no-pager 2>/dev/null \
	| grep -iE 'ASoC|capture|dmic|sdw|error|EIO' \
	| tail -20 | tee "${CB}/kernel-tail.log" || true
echo

# Follow-up: match PW params on Case B
echo "=== CASE B2: arecord PW-matched (-M period 1024 buffer 4096) ==="
CB2="${OUT_DIR}/case-b2-alsa-mmap"
mkdir -p "$CB2"
systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
sleep 2
if arecord -D "$ALSA_DEV" -f S32_LE -r 48000 -c 2 -M \
	--period-size=1024 --buffer-size=4096 -d "$RECORD_SEC" \
	"${CB2}/capture.wav" >"${CB2}/arecord.log" 2>&1; then
	echo "RESULT case-b2=PASS size=$(stat -c%s "${CB2}/capture.wav")"
else
	echo "RESULT case-b2=FAIL"
	tail -5 "${CB2}/arecord.log" || true
fi
_snap "${CB2}" "during" 
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true
sleep 2
echo

# ── Summary diff ────────────────────────────────────────────────────
SUM="${OUT_DIR}/summary.txt"
{
	echo "PW vs ALSA diff summary"
	echo "time=$TS"
	echo "alsa_dev=$ALSA_DEV pcm_proc=$PCM_PROC"
	echo
	echo "=== Case A (pw-record) ==="
	echo -n "wav: "
	[[ -f "${CA}/capture.wav" ]] && stat -c%s "${CA}/capture.wav" || echo missing
	echo "--- hw_params during ---"
	cat "${CA}/during-open-hw_params.txt" 2>/dev/null || echo closed
	echo "--- status during (hw_ptr) ---"
	grep -E '^(state|hw_ptr|appl_ptr|delay|avail)' "${CA}/during-t0-status.txt" 2>/dev/null || true
	echo
	echo "=== Case B (arecord) ==="
	echo -n "wav: "
	[[ -f "${CB}/capture.wav" ]] && stat -c%s "${CB}/capture.wav" || echo missing
	echo "--- arecord log tail ---"
	tail -5 "${CB}/arecord.log" 2>/dev/null || true
	echo "--- hw_params during ---"
	cat "${CB}/during-open-hw_params.txt" 2>/dev/null || echo closed
	echo "--- status during ---"
	grep -E '^(state|hw_ptr|appl_ptr|delay|avail)' "${CB}/during-t0-status.txt" 2>/dev/null || true
	echo
	echo "=== diff hw_params (during-open) ==="
	if [[ -f "${CA}/during-open-hw_params.txt" && -f "${CB}/during-open-hw_params.txt" ]]; then
		diff -u "${CA}/during-open-hw_params.txt" "${CB}/during-open-hw_params.txt" || true
	else
		echo "(one side closed — see individual files)"
	fi
	echo
	echo "=== diff sw_params (during-open) ==="
	if [[ -f "${CA}/during-open-sw_params.txt" && -f "${CB}/during-open-sw_params.txt" ]]; then
		diff -u "${CA}/during-open-sw_params.txt" "${CB}/during-open-sw_params.txt" || true
	else
		echo "(one side closed)"
	fi
	echo
	echo "=== wpctl api.alsa.path (Case A) ==="
	grep -E 'api\.alsa\.(path|pcm|period|format|rate|channels)' "${OUT_DIR}/before/wpctl-inspect-default-source.txt" 2>/dev/null || true
} | tee "$SUM"

echo
echo "diff complete: $OUT_DIR"
echo "summary: $SUM"
