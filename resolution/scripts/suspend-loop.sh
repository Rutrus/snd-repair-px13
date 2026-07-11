#!/usr/bin/env bash
# resolution/scripts/suspend-loop.sh — quick PASS/FAIL loop for workarounds
set -euo pipefail

CYCLES="${1:-3}"
INTERVAL="${INTERVAL:-5}"

log() { echo "[suspend-loop] $*"; }

for i in $(seq 1 "$CYCLES"); do
	log "cycle $i/$CYCLES — suspending in ${INTERVAL}s (Ctrl+C to abort)"
	sleep "$INTERVAL"
	systemctl suspend
	log "resumed — check audio manually or run speaker-test"
	read -r -p "PASS this cycle? [y/N] " ans
	case "${ans,,}" in
	y|yes) log "cycle $i PASS" ;;
	*) log "cycle $i FAIL — stopping"; exit 1 ;;
	esac
done

log "all $CYCLES cycles reported PASS"
