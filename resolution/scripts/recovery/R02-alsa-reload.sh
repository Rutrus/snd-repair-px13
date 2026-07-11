#!/usr/bin/env bash
# R02 — Layer 1: ALSA userspace / px13-audio-fix without PCI reset.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

FIX="${REPO}/scripts/px13-audio-fix.sh"
log "R02: ALSA userspace path (L1)"

if [[ -x "$FIX" ]]; then
	PX13_AFTER_SUSPEND=1 PX13_SKIP_PCI_ON_BOOT=1 PX13_SKIP_PIPEWIRE=1 \
		"$FIX" || true
else
	log "px13-audio-fix.sh not found — applying UCM only"
	if command -v alsaucm >/dev/null 2>&1; then
		card="$(awk '/ProArtPX13/ {gsub(/^[[:space:]]+/, ""); print; exit}' /proc/asound/cards 2>/dev/null)"
		[[ -n "$card" ]] && alsaucm -c "$card" set _verb HiFi 2>/dev/null || true
	fi
fi

sleep 2
witness_audio
log "R02 done — record PASS/FAIL in resolution/TRACKER.md"
