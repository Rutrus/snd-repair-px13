#!/usr/bin/env bash
# PX13 audio stack diagnostic — detect layer, find failure point.
#
# Usage:
#   ./scripts/px13-stack-check.sh
#   ./scripts/px13-stack-check.sh --brief
#
# Exit: 0 = no critical blockers for documented install path; 1 = action needed.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIEF=0
FAIL=0
WARN=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--brief) BRIEF=1; shift ;;
	-h|--help) sed -n '3,10p' "$0"; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

KVER="$(uname -r)"
KO_TAS="/lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst"
KO_SDW="/lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst"
KO_UTILS="/lib/modules/$KVER/kernel/sound/soc/sdw-utils/snd-soc-sdw-utils.ko.zst"

_log() {
	[[ "$BRIEF" -eq 1 ]] && return 0
	printf '%s\n' "$*"
}

_status() {
	local layer="$1" item="$2" result="$3" detail="${4:-}"
	printf '%-4s %-28s %-6s %s\n' "$layer" "$item" "$result" "$detail"
	case "$result" in
	FAIL) FAIL=$((FAIL + 1)) ;;
	WARN) WARN=$((WARN + 1)) ;;
	esac
}

_ko_strings() {
	local ko="$1"
	[[ -f "$ko" ]] || return 1
	zstd -d -c "$ko" 2>/dev/null | strings
}

_module_flavor() {
	local ko="$1"
	local kind="${2:-tas}"
	local s
	s="$(_ko_strings "$ko" 2>/dev/null || true)"
	if [[ "$kind" == sdw ]]; then
		if grep -Fq 'PHASE7 ctx=amd fn=manual_irq_schedule' <<<"$s"; then
			echo "W1-resume"
		else
			echo "stock"
		fi
		return
	fi
	if grep -Fq 'W3 ctx=dapm' <<<"$s"; then echo "W3-diagnostic"
	elif grep -Fq 'W2 ctx=tas fn=force_fw_reinit' <<<"$s"; then echo "W2-resume"
	elif grep -Fq 'ENZOPLAY' <<<"$s"; then echo "lab-ENZOPLAY"
	elif grep -Fq 'skip capture without source' <<<"$s" || \
	     grep -Fq 'fw retry' <<<"$s" || \
	     grep -Fq 'wait fw' <<<"$s"; then echo "upstream-ABC"
	else echo "stock"
	fi
}

_vermagic_ok() {
	local mod="$1"
	modinfo "$mod" 2>/dev/null | grep -q "vermagic:.*$KVER"
}

echo "=== PX13 audio stack check ==="
_log "time=$(date -Iseconds) kernel=$KVER repo=$REPO"
_log ""

# --- L0: kernel / modules present ---
if [[ -f "$KO_TAS" ]]; then
	_status L0 "snd-soc-tas2783-sdw" PASS "$(basename "$KO_TAS")"
else
	_status L0 "snd-soc-tas2783-sdw" FAIL "missing $KO_TAS"
fi

if _vermagic_ok snd_soc_tas2783_sdw; then
	_status L0 "vermagic tas2783" PASS "$KVER"
else
	_status L0 "vermagic tas2783" FAIL "mismatch or module not loaded"
fi

FLAVOR_TAS="$(_module_flavor "$KO_TAS" tas 2>/dev/null || echo unknown)"
FLAVOR_SDW="$(_module_flavor "$KO_SDW" sdw 2>/dev/null || echo unknown)"
_status L1 "module flavor tas2783" INFO "$FLAVOR_TAS"
_status L1 "module flavor soundwire-amd" INFO "$FLAVOR_SDW"

W2_OK=0 W1_OK=0
[[ "$FLAVOR_TAS" == W2-resume || "$FLAVOR_TAS" == W3-diagnostic ]] && W2_OK=1
[[ "$FLAVOR_SDW" == W1-resume ]] && W1_OK=1

case "$FLAVOR_TAS" in
stock)
	_status L2 "upstream A+B+C" FAIL "stock driver — run build-from-upstream.sh"
	_status L3 "W1+W2 resume" FAIL "not installed — run build-w1-w2.sh after L2"
	;;
upstream-ABC)
	_status L2 "upstream A+B+C" PASS "patched module installed"
	_status L3 "W1+W2 resume" FAIL "W2 missing — run build-w1-w2.sh"
	;;
W2-resume|W3-diagnostic)
	_status L2 "upstream A+B+C" PASS "base + W2 present"
	if [[ "$W1_OK" -eq 1 ]]; then
		_status L3 "W1+W2 resume" PASS "W2 + W1 installed"
	else
		_status L3 "W1+W2 resume" FAIL "W2 OK but soundwire-amd stock — re-run build-w1-w2.sh"
	fi
	;;
*) _status L2 "module detect" WARN "unknown flavor: $FLAVOR_TAS" ;;
esac

if [[ "$FLAVOR_SDW" == stock ]]; then
	_status L3 "soundwire-amd W1" FAIL "stock — run build-w1-w2.sh (W1 phase7)"
elif [[ "$FLAVOR_SDW" == W1-resume ]]; then
	_status L3 "soundwire-amd W1" PASS "$FLAVOR_SDW"
elif [[ "$FLAVOR_SDW" != unknown ]]; then
	_status L3 "soundwire-amd W1" WARN "unexpected: $FLAVOR_SDW"
fi

# --- L1: user layer (firmware, UCM, services) ---
FW_OK=0
for f in /lib/firmware/1714-1-8.bin /lib/firmware/1714-1-B.bin \
	 /lib/firmware/ti/audio/tas2783/1714-1-8.bin; do
	[[ -f "$f" ]] && FW_OK=1 && break
done
if [[ "$FW_OK" -eq 1 ]]; then
	_status L1 "firmware .bin" PASS "TAS2783 calibration present"
else
	_status L1 "firmware .bin" FAIL "run brainchillz fix-px13-audio.sh"
fi

UCM="$(find /usr/share/alsa/ucm2 -name '*ProArtPX13*' -o -name 'tas2783.conf' 2>/dev/null | head -1)"
if [[ -n "$UCM" ]]; then
	_status L1 "UCM profile" PASS "$(basename "$UCM")"
else
	_status L1 "UCM profile" FAIL "brainchillz or install-ucm-px13.sh"
fi

_systemctl_enabled() {
	local unit="$1"
	local out
	out="$(systemctl is-enabled "$unit" 2>&1)" || true
	out="${out%%$'\n'*}"
	printf '%s' "${out:-missing}"
}

REBIND="$(_systemctl_enabled px13-audio-rebind.service)"
RESUME="$(_systemctl_enabled px13-audio-resume.service)"
_status L1 "px13-audio-rebind" INFO "$REBIND"

if [[ "$FLAVOR_TAS" == W2-resume || "$FLAVOR_TAS" == W3-diagnostic ]]; then
	if [[ "$RESUME" == disabled ]]; then
		_status L1 "px13-audio-resume" PASS "disabled (required with W1+W2)"
	else
		_status L1 "px13-audio-resume" FAIL "must disable with W1+W2 — causes Dummy Output"
	fi
else
	_status L1 "px13-audio-resume" INFO "$RESUME (enable only without W1+W2)"
fi

# --- L4: runtime enumeration ---
if grep -q amdsoundwire /proc/asound/cards 2>/dev/null; then
	_status L4 "card amdsoundwire" PASS "$(grep amdsoundwire /proc/asound/cards)"
else
	_status L4 "card amdsoundwire" FAIL "no SoundWire card"
fi

SDW_N="$(ls /sys/bus/soundwire/devices/ 2>/dev/null | grep -c '^sdw:' || echo 0)"
if [[ "$SDW_N" -ge 3 ]]; then
	_status L4 "soundwire slaves" PASS "$SDW_N devices"
else
	_status L4 "soundwire slaves" WARN "expected ≥3, got $SDW_N"
fi

if command -v wpctl >/dev/null 2>&1; then
	if wpctl status 2>/dev/null | grep -qiE 'Dummy Output|Dummy-Driver'; then
		_status L4 "PipeWire sink" FAIL "Dummy Output — L1 or FW broken"
	elif wpctl status 2>/dev/null | grep -qi 'Audio Coprocessor Speaker'; then
		_status L4 "PipeWire sink" PASS "Speaker visible"
	else
		_status L4 "PipeWire sink" WARN "no Speaker sink in wpctl"
	fi
else
	_status L4 "PipeWire" WARN "wpctl not found"
fi

# --- L5: kernel health signals ---
KLOG="$(journalctl -k -b 0 --no-pager 2>/dev/null || true)"
SUSPEND_N="$(grep -c 'PM: suspend entry' <<<"$KLOG" 2>/dev/null || true)"
SUSPEND_N="${SUSPEND_N:-0}"
_status L5 "suspend this boot" INFO "count=$SUSPEND_N"

if grep -q 'error playback without fw download' <<<"$KLOG"; then
	_status L5 "dmesg fw download" FAIL "playback without fw"
elif grep -q 'Direct firmware load for.*failed' <<<"$KLOG"; then
	_status L5 "dmesg fw load" FAIL "firmware load failed"
else
	_status L5 "dmesg fw load" PASS "no fw load errors"
fi

if grep -q 'failed to resume: error -110' <<<"$KLOG"; then
	_status L5 "dmesg S2 -110" FAIL "tas2783 resume timeout (need W1+W2 or reboot)"
elif grep -q 'Program params failed: -22' <<<"$KLOG"; then
	_status L5 "dmesg capture -22" WARN "SDW program -22 (upstream series A helps)"
else
	_status L5 "dmesg resume/capture" PASS "no -110/-22 in this boot log"
fi

# --- Recommended next step ---
_log ""
_log "=== Recommended next step ==="
if [[ "$FLAVOR_TAS" == stock ]]; then
	_log "1. ./scripts/prepare-kernel-tree.sh"
	_log "2. ./scripts/build-from-upstream.sh && sudo reboot"
	_log "3. sudo ./scripts/build-w1-w2.sh && sudo reboot"
	_log "4. sudo ./scripts/install-ucm-px13.sh (if mic missing)"
	_log "5. ./scripts/post-s2-user-witness.sh"
elif [[ "$FLAVOR_TAS" == upstream-ABC ]]; then
	_log "1. sudo ./scripts/build-w1-w2.sh && sudo reboot"
	_log "2. sudo systemctl disable --now px13-audio-resume.service"
	_log "3. ./scripts/post-s2-user-witness.sh"
elif [[ "$W2_OK" -eq 1 && "$W1_OK" -eq 1 ]]; then
	if [[ "$RESUME" != disabled ]]; then
		_log "1. sudo systemctl disable --now px13-audio-resume.service"
		_log "2. ./scripts/post-s2-user-witness.sh"
	else
		_log "W1+W2 installed — verify:"
		_log "  speaker-test -D pipewire -c 2 -t sine -f 440 -l 1"
		_log "  ./scripts/post-s2-user-witness.sh"
	fi
elif [[ "$SUSPEND_N" -gt 0 ]] && grep -q 'failed to resume: error -110' <<<"$KLOG"; then
	_log "Reboot to clear post-S2 -110, then install W1+W2 if not done."
else
	_log "Stack looks installed — run verification:"
	_log "  speaker-test -D pipewire -c 2 -t sine -f 440 -l 1"
	_log "  ./scripts/post-s2-user-witness.sh"
fi

_log ""
_log "Protocol: docs/INSTALL-VERIFY-PROTOCOL.md"
_log "summary: fail=$FAIL warn=$WARN"

[[ "$FAIL" -eq 0 ]]
