#!/usr/bin/env bash
# Quick playback/userspace diagnostic (no suspend).
# Usage: sudo ./s2-audio-probe.sh
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_SCRIPT_DIR}/recovery/_lib.sh"

dummy_def=no
userspace_default_sink_is_dummy && dummy_def=yes

cat <<EOF
=== S2 AUDIO PROBE ===
Card:          $(alsa_card_present && echo present || echo missing)
ALSA dev:      ${PX13_ALSA_DEV:-$(alsa_speaker_dev 2>/dev/null || echo ?)}
ALSA playback: $(witness_playback_alsa && echo PASS || echo FAIL)
Userspace:     $(userspace_sink_state)
Default dummy: ${dummy_def}
Full witness:  $(witness_playback && echo PASS || echo FAIL)
Post-resume S2: $(post_resume_audio_broken && echo yes || echo no)
Note: Dummy Output may PASS speaker-test with no audible sound — ALSA plughw is authoritative.
======================
EOF
