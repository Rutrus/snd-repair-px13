#!/usr/bin/env bash
# Assess S2 witness quality after the most recent suspend (no recovery).
# Usage: sudo ./s2-oracle.sh [journal-since-window]
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${_SCRIPT_DIR}/recovery/_lib.sh"

# shellcheck source=/dev/null
source "$LIB"

WINDOW="${1:-$(witness_journal_since "5 min ago")}"

export RESOLUTION_ASSUME_SUSPEND=1

assess_witness_quality "$WINDOW"

valid_word=INVALID
[[ "${RESOLUTION_WITNESS_VALID:-0}" == "1" ]] && valid_word=VALID

cat <<EOF
=== S2 WITNESS ORACLE ===
Quality:     ${RESOLUTION_WITNESS_QUALITY} ($(witness_quality_label))
Valid:       ${valid_word} (min ${RESOLUTION_MIN_WITNESS:-W2})
Reason:      ${RESOLUTION_WITNESS_REASON}
Userspace:   ${RESOLUTION_USERSPACE_STATE:-$(userspace_sink_state)} (dummy simulates playback — not real audio)
Default:     $(userspace_default_sink_is_dummy && echo dummy || echo hardware)
ALSA:        $(witness_playback_alsa && echo pass || echo fail)
Playback:    $(witness_playback && echo pass || echo fail) (never counts dummy as OK when card present)
Research:    -110 ∧ handler_since_pm=0 ∧ STAT1=0x4 → W3+
=========================
EOF

[[ "$valid_word" == VALID ]]
