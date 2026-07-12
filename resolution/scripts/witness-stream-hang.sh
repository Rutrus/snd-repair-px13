#!/usr/bin/env bash
# Capture ALSA/stream hang state while speaker-test (or aplay) is blocked.
# Run in a second terminal WHILE playback is stuck.
#
# Usage:
#   sudo ./resolution/scripts/witness-stream-hang.sh
#   sudo ./resolution/scripts/witness-stream-hang.sh <PID>
#
# Env:
#   WITNESS_PTR_SAMPLES=25
#   WITNESS_PTR_INTERVAL_MS=500   # 500 ms between samples
set -euo pipefail
export LC_ALL=C LC_NUMERIC=C

TS="$(date -Iseconds)"
PID="${1:-}"
PCM_STATUS="/proc/asound/card1/pcm2p/sub0/status"
SAMPLES="${WITNESS_PTR_SAMPLES:-25}"
INTERVAL_MS="${WITNESS_PTR_INTERVAL_MS:-500}"

if [[ -z "$PID" ]]; then
	PID="$(pgrep -n 'speaker-test|aplay' 2>/dev/null || true)"
fi

_pcm_fields() {
	grep -E '^(state|hw_ptr|appl_ptr|avail|delay)[[:space:]]*:' "$PCM_STATUS" 2>/dev/null \
		| tr -s ' ' || true
}

_pcm_val() {
	# ALSA status uses "hw_ptr      : 271312" (spaces before colon)
	echo "$1" | awk -F':' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}'
}

_pcm_state() {
	grep -E '^state[[:space:]]*:' "$PCM_STATUS" 2>/dev/null | awk -F':' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' || true
}

_irq_audio_lines() {
	grep -iE 'snd|acp|sound|HDA|sdw|160:|dma' /proc/interrupts 2>/dev/null || true
}

_irq_acp_count() {
	grep 'ACP_PCI_IRQ' /proc/interrupts 2>/dev/null | awk '{
		s=0
		for (i=2; i<NF; i++)
			if ($i ~ /^[0-9]+$/) s+=$i
		print s
	}' || true
}

_sleep_interval() {
	# bash sleep accepts fractional seconds; LC_NUMERIC=C avoids locale issues
	local sec
	sec="$(awk "BEGIN {printf \"%.3f\", ${INTERVAL_MS}/1000}")"
	sleep "$sec"
}

echo "=== WITNESS STREAM HANG === time=$TS pid=${PID:-none}"
echo

if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
	echo "--- ps ---"
	ps -o pid,ppid,state,wchan:32,cmd -p "$PID" 2>/dev/null || true
	echo
	if [[ -r "/proc/$PID/stack" ]]; then
		echo "--- /proc/$PID/stack ---"
		cat "/proc/$PID/stack" 2>/dev/null || true
		echo
	fi
	if [[ -r "/proc/$PID/wchan" ]]; then
		echo "--- wchan ---"
		cat "/proc/$PID/wchan" 2>/dev/null || true
		echo
	fi
else
	echo "WARNING: no live speaker-test/aplay PID."
	echo "  Run this script in terminal 2 WHILE terminal 1 is blocked in speaker-test."
	echo
fi

pcm_state="$(_pcm_state)"
if [[ "$pcm_state" != "RUNNING" ]]; then
	echo "WARNING: PCM2 state=${pcm_state:-unknown} (need RUNNING for pointer series)."
	echo
fi

echo "--- card1 pcm2 hw_params ---"
cat /proc/asound/card1/pcm2p/sub0/hw_params 2>/dev/null || echo "(closed or unavailable)"
echo

if [[ -r "$PCM_STATUS" && "$pcm_state" == "RUNNING" ]]; then
	echo "--- pcm2 pointer time series (${SAMPLES} x ${INTERVAL_MS}ms) ---"
	echo "# classify: hw_ptr frozen=stall C, slow=starvation B, both ptrs flat=blocked A"
	dly0="" av0=""
	i=0
	while [[ "$i" -lt "$SAMPLES" ]]; do
		line="$(_pcm_fields)"
		hw="$(_pcm_val "$(echo "$line" | grep hw_ptr)")"
		ap="$(_pcm_val "$(echo "$line" | grep appl_ptr)")"
		dly="$(_pcm_val "$(echo "$line" | grep delay)")"
		av="$(_pcm_val "$(echo "$line" | grep avail)")"
		t_ms=$((i * INTERVAL_MS))
		printf 't=%dms hw=%s appl=%s delay=%s avail=%s' "$t_ms" "${hw:-?}" "${ap:-?}" "${dly:-?}" "${av:-?}"
		if [[ "$dly" =~ ^[0-9]+$ && "$dly0" =~ ^[0-9]+$ ]]; then
			printf ' d_delay=%s' "$((dly - dly0))"
		fi
		if [[ "$av" =~ ^[0-9]+$ && "$av0" =~ ^[0-9]+$ ]]; then
			printf ' d_avail=%s' "$((av - av0))"
		fi
		echo
		[[ "$dly" =~ ^[0-9]+$ ]] && dly0="$dly"
		[[ "$av" =~ ^[0-9]+$ ]] && av0="$av"
		i=$((i + 1))
		[[ "$i" -lt "$SAMPLES" ]] && _sleep_interval
	done
	echo
elif [[ ! -r "$PCM_STATUS" ]]; then
	echo "(skip pointer series — $PCM_STATUS missing)"
	echo
fi

echo "--- /proc/interrupts (audio-related) snapshot 1 ---"
_irq_audio_lines
irq1="$(_irq_acp_count)"
echo "# ACP_PCI_IRQ cpu-total (approx): ${irq1:-?}"
echo
sleep 2
echo "--- /proc/interrupts (audio-related) snapshot 2 (+2s) ---"
_irq_audio_lines
irq2="$(_irq_acp_count)"
echo "# ACP_PCI_IRQ cpu-total (approx): ${irq2:-?}"
if [[ "$irq1" =~ ^[0-9]+$ && "$irq2" =~ ^[0-9]+$ ]]; then
	echo "# d_irq_2s=$((irq2 - irq1))"
fi
echo

echo "--- full pcm2 status ---"
cat "$PCM_STATUS" 2>/dev/null || echo "(unavailable)"
echo

echo "--- fuser /dev/snd ---"
fuser -v /dev/snd/* 2>&1 || true
echo

echo "--- recent kernel (audio) ---"
journalctl -k -b 0 --since '3 min ago' --no-pager 2>/dev/null \
	| grep -iE 'deprepare|trigger|hw_free|close|ASoC|fw download|Invalid device|timeout|tas2783|sdw_|dma' \
	| tail -40 || true
