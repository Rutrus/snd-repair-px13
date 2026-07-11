#!/usr/bin/env bash
# R10 — Layer 7: secondary system suspend → resume.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

log "R10: secondary suspend (L7) — will suspend in 5s (Ctrl+C to abort)"
sleep 5
systemctl suspend
log "R10: resumed — waiting 5s for stack settle"
sleep 5
witness_audio
log "R10 done — record PASS/FAIL in resolution/TRACKER.md"
