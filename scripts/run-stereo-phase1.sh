#!/bin/bash
# Fase 1+2: prueba canales L/R y recoge ENZOPLAY del kernel
set -euo pipefail

LOG="${1:-${HOME}/tas2783-stereo-phase1.log}"
DEV="plughw:1,2"

kmlog() {
	journalctl -k -b 0 --no-pager 2>/dev/null | grep ENZOPLAY || dmesg 2>/dev/null | grep ENZOPLAY || true
}

run_test() {
	local label="$1"
	local speaker="$2"

	{
		echo "===== $(date -Is) $label speaker=$speaker ====="
		echo "--- ENZOPLAY antes ---"
		kmlog | tail -5
	} >>"$LOG"

	echo ">>> $label (speaker $speaker) — anota qué oyes"
	speaker-test -D "$DEV" -c 2 -t wav -l 1 -s "$speaker" || true

	{
		echo "--- ENZOPLAY después ---"
		kmlog | tail -40
		echo ""
	} >>"$LOG"
}

: >"$LOG"
run_test "LEFT-only" 1
run_test "RIGHT-only" 2

echo "Log: $LOG"
grep -E 'ENZOPLAY|ch_map' "$LOG" | sed 's/^/  /' || echo "(sin ENZOPLAY — instala módulos 0008 y reboot)"
