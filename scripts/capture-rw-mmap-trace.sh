#!/usr/bin/env bash
# Trace kernel ALSA path during RW vs MMAP capture (Branch B — first divergence).
#
# Requires root (dynamic_debug). PipeWire stopped for exclusive hw: access.
#
# Usage:
#   sudo ./scripts/capture-rw-mmap-trace.sh
#   sudo ./scripts/capture-rw-mmap-trace.sh --label post-s2 --device hw:1,4
#
# Log: /var/log/snd-repair/capture-rw-mmap-<label>-*.log
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LABEL="post-s2"
DEV="${CAPTURE_TRACE_DEV:-hw:1,4}"
FMT="${CAPTURE_TRACE_FORMAT:-S32_LE}"
RECORD_SEC="${CAPTURE_TRACE_SEC:-1}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="$2"; shift 2 ;;
	--device) DEV="$2"; shift 2 ;;
	--format) FMT="$2"; shift 2 ;;
	-h|--help)
		sed -n '3,14p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

if [[ "$(id -u)" -ne 0 ]]; then
	echo "FAIL: run as root (dynamic_debug)" >&2
	exit 1
fi

LOG_DIR="${CAPTURE_TRACE_LOG_DIR:-/var/log/snd-repair}"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/capture-rw-mmap-${LABEL}-$(date +%Y%m%dT%H%M%S).log"

exec > >(tee -a "$LOG") 2>&1

section() { echo; echo "========== $* =========="; }

echo "=== CAPTURE RW vs MMAP KERNEL TRACE ==="
echo "label=$LABEL time=$(date -Iseconds) dev=$DEV fmt=$FMT"
echo "log=$LOG kernel=$(uname -r)"
echo

section "Stop PipeWire (user $UID_SELF)"
sudo -u "#${UID_SELF}" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
	systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
sleep 2

section "debugfs"
DBGCTL="/sys/kernel/debug/dynamic_debug/control"
if [[ ! -d /sys/kernel/debug ]]; then
	mount -t debugfs debugfs /sys/kernel/debug
fi
[[ -w "$DBGCTL" ]] || { echo "FAIL: $DBGCTL not writable"; exit 1; }

DEFAULT_MODULES=(
	snd_pcm
	snd_soc_core
	snd_soc_sdw_utils
	snd_acp_pcm
	snd_acp_legacy_common
	snd_acp_sdw_legacy_mach
	snd_soc_rt721_sdca
	soundwire_bus
	soundwire_amd
)
read -r -a EXTRA <<<"${CAPTURE_TRACE_MODULES:-}"

section "Enable dynamic_debug"
for m in "${DEFAULT_MODULES[@]}" "${EXTRA[@]}"; do
	[[ -n "$m" ]] && echo "module ${m} +p" >>"$DBGCTL" 2>/dev/null || true
done
for spec in \
	'func snd_pcm_readi +p' \
	'func snd_pcm_mmap_capture +p' \
	'func snd_pcm_lib_read +p' \
	'func snd_pcm_lib_mmap +p' \
	'func pcm_lib_copy +p' \
	'func snd_soc_pcm_pointer +p' \
	'func soc_pcm_copy +p' \
	; do
	echo "$spec" >>"$DBGCTL" 2>/dev/null || true
done

capture_probe() {
	local tag="$1"
	shift
	local mark wav log
	mark="$(dmesg 2>/dev/null | wc -l | tr -d ' ')"
	wav="${LOG}.${tag}.wav"
	log="${LOG}.${tag}.log"
	section "Capture probe: $tag"
	echo "cmd: $*"
	if "$@" >"$log" 2>&1; then
		echo "result: PASS bytes=$(stat -c%s "$wav" 2>/dev/null || echo 0)"
	else
		echo "result: FAIL rc=$?"
		tail -5 "$log" || true
	fi
	echo "--- dmesg NEW (filtered) ---"
	dmesg 2>/dev/null | tail -n +"$((mark + 1))" | \
		grep -Ei 'copy|mmap|readi|pointer|EIO|ASoC error|sdw_|rt721|acp|pcm_' | tail -40 || \
		echo "(no matching lines — widen CAPTURE_TRACE_MODULES)"
	echo "--- dmesg NEW (tail 25) ---"
	dmesg 2>/dev/null | tail -n +"$((mark + 1))" | tail -25
	echo
}

section "Probe order: MMAP then RW (MMAP often leaves stream usable)"
capture_probe mmap \
	arecord -D "$DEV" -f "$FMT" -r 48000 -c 2 -d "$RECORD_SEC" \
	-M --period-size=1024 --buffer-size=4096 "$LOG.mmap.wav"
sleep 1
capture_probe rw \
	arecord -D "$DEV" -f "$FMT" -r 48000 -c 2 -d "$RECORD_SEC" \
	"$LOG.rw.wav"

section "Restart PipeWire"
sudo -u "#${UID_SELF}" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
	systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

section "Compare hint"
echo "Diff filtered sections between mmap and rw probes in $LOG"
echo "Goal: first function present in RW failure path but not MMAP success path."
echo "==========================="
