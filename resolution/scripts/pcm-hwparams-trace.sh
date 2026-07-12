#!/usr/bin/env bash
# Capture kernel dynamic_debug lines during a single hw:1,2 open attempt.
# Goal: identify which driver callback returns -EINVAL on snd_pcm_hw_params().
#
# Usage:
#   sudo ./pcm-hwparams-trace.sh [--label S2] [--dual-path]
#   sudo ./pcm-hwparams-trace.sh --label S0 --dual-path   # S0 vs S2 compare
#
# Log: /var/log/snd-repair/pcm-trace-<label>-*.log
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=recovery/_lib.sh
source "${_SCRIPT_DIR}/recovery/_lib.sh"

require_root "$0"

LABEL="S2"
DUAL_PATH=0
SKIP_PRE_WITNESS=0
PROBE_ORDER="pcm0,pcm2"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--label) LABEL="${2:?}"; shift 2 ;;
	--dual-path) DUAL_PATH=1; shift ;;
	--skip-pre-witness) SKIP_PRE_WITNESS=1; shift ;;
	--probe-order) PROBE_ORDER="${2:?}"; shift 2 ;;
	-h | --help)
		cat <<EOF
Usage: sudo $0 [--label S0|S2] [--dual-path] [--skip-pre-witness] [--probe-order pcm2,pcm0]

Enables dynamic_debug, runs aplay probe(s), dumps new dmesg.
  --dual-path          probe hw:CARD,0 then hw:CARD,2 (or --probe-order)
  --skip-pre-witness   do not open PCMs before trace (avoids EBUSY / coupling)
  --probe-order        comma list: pcm0, pcm2 (default) or pcm2,pcm0

Env: PCM_TRACE_MODULES, PCM_TRACE_DEV (SmartAmp device, default hw:1,2)
EOF
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
done

LOG_DIR="${PCM_TRACE_LOG_DIR:-/var/log/snd-repair}"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG="${LOG_DIR}/pcm-trace-${LABEL}-$(date +%Y%m%dT%H%M%S).log"

DEV="${PCM_TRACE_DEV:-$(alsa_hw_dev 2>/dev/null || echo hw:1,2)}"
CARD="${DEV#hw:}"
CARD="${CARD%%,*}"
DEV_PCM0="hw:${CARD},0"

DEFAULT_MODULES=(
	snd_soc_core
	snd_pcm
	snd_soc_sdw_utils
	snd_pci_ps
	snd_acp_sdw_legacy_mach
	snd_acp_sdw_mach
	snd_soc_tas2783_sdw
	soundwire_bus
	soundwire_amd
)
# User-tunable extra modules (e.g. tas2783 if built-in name differs)
read -r -a EXTRA_MODULES <<<"${PCM_TRACE_MODULES:-}"

exec > >(tee -a "$LOG") 2>&1

section() { echo; echo "========== $* =========="; }

echo "=== PCM HW_PARAMS TRACE ==="
echo "label: ${LABEL}"
echo "time: $(date -Iseconds)"
echo "dev_pcm2: ${DEV}"
echo "dev_pcm0: ${DEV_PCM0}"
echo "dual_path: ${DUAL_PATH}"
echo "log: ${LOG}"
echo "kernel: $(uname -r)"
echo

section "Pre-state witness"
if [[ "$SKIP_PRE_WITNESS" -eq 1 ]]; then
	echo "skipped (--skip-pre-witness)"
else
	echo "pcm0=$(witness_pcm_try_aplay "hw:${CARD},0" && echo pass || echo "${WITNESS_PCM_LAST_CLASS}")"
	echo "pcm2=$(witness_pcm_try_aplay "${DEV}" && echo pass || echo "${WITNESS_PCM_LAST_CLASS}")"
	echo "stderr_pcm2: ${WITNESS_PCM_LAST_ERR:-<none>}"
	sleep 2
fi
echo

section "debugfs mount"
DBGCTL="/sys/kernel/debug/dynamic_debug/control"
if [[ ! -d /sys/kernel/debug ]]; then
	mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || {
		echo "FAIL: cannot mount debugfs"
		exit 1
	}
	echo "mounted debugfs"
fi
[[ -w "$DBGCTL" ]] || { echo "FAIL: ${DBGCTL} not writable"; exit 1; }
echo "debugfs OK"
echo

section "Save dynamic_debug snapshot (head)"
cp "$DBGCTL" "${LOG}.ddbg.before" 2>/dev/null || true
wc -l "${LOG}.ddbg.before" 2>/dev/null || true
echo

enable_module_debug() {
	local m="$1"
	if [[ -d "/sys/module/${m}" ]] || grep -q "^${m} " /proc/modules 2>/dev/null; then
		echo "module ${m} +p" >>"$DBGCTL"
		echo "  enabled: ${m}"
		return 0
	fi
	# built-in: try anyway
	echo "module ${m} +p" >>"$DBGCTL" 2>/dev/null && echo "  enabled (builtin?): ${m}" || \
		echo "  skip: ${m} (not loaded)"
}

section "Enable dynamic_debug (target modules only)"
for m in "${DEFAULT_MODULES[@]}" "${EXTRA_MODULES[@]}"; do
	[[ -n "$m" ]] && enable_module_debug "$m"
done
# High-signal function filters (kernel may ignore unknown specs — harmless)
for spec in \
	'func snd_pcm_hw_params +p' \
	'func snd_soc_pcm_hw_params +p' \
	'func soc_pcm_hw_params +p' \
	'func dapm* +p' \
	; do
	echo "$spec" >>"$DBGCTL" 2>/dev/null || true
done
echo

probe_pcm() {
	local tag="$1" dev="$2"
	local mark
	mark="$(dmesg 2>/dev/null | wc -l | tr -d ' ')"
	section "Probe ${tag}: ${dev}"
	echo "--- dump-hw-params ---"
	aplay --dump-hw-params -D "$dev" /dev/zero 2>&1 || echo "dump-hw-params: rc=$?"
	echo "--- aplay S16_LE 48kHz 2ch 1s ---"
	aplay -D "$dev" -f S16_LE -c 2 -r 48000 -t raw -d 1 -q /dev/zero 2>&1 || echo "aplay: rc=$?"
	echo "--- dmesg NEW (filtered) since probe start (line ${mark}) ---"
	dmesg 2>/dev/null | tail -n +"$((mark + 1))" | \
		grep -Ei 'hw_params|EINVAL|tas2783|rt721|dapm|soc_pcm|snd_pcm|multicodec|acp|soundwire|reject|invalid|unsupported|not prepared|link' || \
		echo "(no matching lines)"
	echo "--- dmesg NEW (full tail) ---"
	dmesg 2>/dev/null | tail -n +"$((mark + 1))" | tail -40
	echo
}

DMESG_MARK="$(dmesg 2>/dev/null | wc -l | tr -d ' ')"
echo "dmesg lines before probes: ${DMESG_MARK}"
echo

if [[ "$DUAL_PATH" -eq 1 ]]; then
	IFS=',' read -r -a _order <<<"$PROBE_ORDER"
	for slot in "${_order[@]}"; do
		slot="${slot// /}"
		case "$slot" in
		pcm0) probe_pcm "PCM0 control RT721" "$DEV_PCM0" ;;
		pcm2) probe_pcm "PCM2 SmartAmp TAS2783" "$DEV" ;;
		*) echo "unknown probe slot: $slot" >&2; exit 1 ;;
		esac
		sleep 2
	done
else
	probe_pcm "PCM2 SmartAmp" "$DEV"
fi

section "dmesg NEW lines since all probes (combined filter)"
dmesg 2>/dev/null | tail -n +"$((DMESG_MARK + 1))" | \
	grep -Ei 'hw_params|EINVAL|tas2783|rt721|dapm|soc_pcm|snd_pcm|multicodec|acp|soundwire|reject|invalid|unsupported|not prepared|link' || \
	echo "(no matching lines — try PCM_TRACE_MODULES or func filter)"
echo

section "dmesg NEW lines (full, last 80)"
dmesg 2>/dev/null | tail -n +"$((DMESG_MARK + 1))" | tail -80
echo

section "Format matrix (quick — pcm2 only)"
dev2="${DEV}"
printf '%-10s %-8s %-4s %-18s\n' FMT RATE CH RESULT
for row in \
	'S16_LE:48000:2' \
	'S16_LE:44100:2' \
	'S24_LE:48000:2' \
	'S32_LE:48000:2' \
	'S16_LE:48000:1' \
	; do
	IFS=: read -r fmt rate ch <<<"$row"
	errfile="$(mktemp)"
	rc=0
	timeout 4 aplay -D "$dev2" -f "$fmt" -r "$rate" -c "$ch" -t raw -d 1 -q /dev/zero 2>"$errfile" || rc=$?
	err="$(tr '\n' ' ' <"$errfile")"
	rm -f "$errfile"
	if [[ "$rc" -eq 0 ]]; then
		res=PASS
	elif echo "$err" | grep -qiE 'set_params|EINVAL|Argumento inválido'; then
		res=EINVAL
	else
		res="fail($rc)"
	fi
	printf '%-10s %-8s %-4s %-18s\n' "$fmt" "$rate" "$ch" "$res"
done
echo "All EINVAL → structural (link/DAPM state). Mixed → capability shrink."
echo

section "Restore hint"
echo "To disable debug noise:"
echo "  echo 'module snd_soc_core -p' | sudo tee /sys/kernel/debug/dynamic_debug/control"
echo "  (or reboot)"
echo
echo "Compare: diff -u /var/log/snd-repair/pcm-trace-S0-*.log /var/log/snd-repair/pcm-trace-S2-*.log"
echo "==========================="
