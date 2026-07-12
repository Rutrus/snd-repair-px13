#!/usr/bin/env bash
# S110 — Drop all ALSA PCM/control users.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="S110"
salvage_log "step ${SID}: drop PCM nodes"
salvage_drop_pcm_nodes
sleep 2
bf_strategy_finish "$SID"
