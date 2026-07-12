#!/usr/bin/env bash
# Rescue runner — aggression tree A→I until strict PASS.
# Usage:
#   sudo run-rescue.sh --from-s2
#   sudo run-rescue.sh --from-s2 --level C
#   sudo run-rescue.sh --list
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

FROM_S2=0
LEVEL=""
LIST=0
INCLUDE_HI=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--from-s2) FROM_S2=1 ;;
	--level) LEVEL="${2:?}"; shift ;;
	--include-hi) INCLUDE_HI=1 ;;
	--list) LIST=1 ;;
	-h | --help)
		cat <<EOF
Usage: sudo $0 [--from-s2] [--level C] [--include-hi] [--list]

Aggression tree (default A→G):
  A  restart PipeWire
  B  ALSA restore + udev
  C  FULL stack destroy (SOF+SW+snd_pci_ps) + rebuild  ★ key level
  D  PCI remove+rescan
  E  unbind all SoundWire
  F  PCI remove + 10s settle + reload
  G  second suspend
  H  kexec (RESCUE_ALLOW_KEXEC=1)
  I  reboot (RESCUE_ALLOW_REBOOT=1)

Prereq: s2-reproduce.sh must certify S2 first.
EOF
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
	shift
done

require_root "$0"
rescue_ensure_logdir

INDEX="${REPO}/resolution/rescue/levels.yaml"
[[ -f "$INDEX" ]] || { echo "missing $INDEX" >&2; exit 1; }

resolve_levels() {
	python3 - "$INDEX" "$LEVEL" "$INCLUDE_HI" <<'PY'
import sys, yaml
idx, level, hi = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
with open(idx) as f:
    d = yaml.safe_load(f)
levels = d["levels"]
order = d.get("default_order", [])
out = []
if level:
    if level in levels:
        out.append((level, levels[level]["script"]))
else:
    for lid in order:
        out.append((lid, levels[lid]["script"]))
    if hi:
        for lid in ("H", "I"):
            if lid in levels:
                out.append((lid, levels[lid]["script"]))
for lid, scr in out:
    print(f"{lid}\t{scr}")
PY
}

if [[ "$LIST" == "1" ]]; then
	echo "Rescue aggression tree:"
	python3 - "$INDEX" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f)
for lid in d.get("default_order", []):
    L = d["levels"][lid]
    print(f"  {lid}: {L.get('destroys','?')}")
PY
	exit 0
fi

if [[ "$FROM_S2" == "1" ]]; then
	rescue_log "certifying S2"
	bf_certify_s2_entry || {
		rescue_log "abort: not in S2 — run s2-reproduce.sh first"
		exit 2
	}
fi

rescue_log "log: ${RESCUE_LOG_DIR}"
rescue_log "question: ANY sequence restores audio without reboot?"

while IFS=$'\t' read -r lid scr; do
	[[ "$FROM_S2" == "1" ]] && ! bf_require_s2_before_strategy && {
		rescue_log "skip ${lid}: no longer in S2"
		continue
	}
	script="${SCRIPT_DIR}/levels/${scr}"
	[[ -x "$script" ]] || chmod +x "$script"
	logf="${RESCUE_LOG_DIR}/$(date +%Y%m%dT%H%M%S)-${lid}.log"
	rescue_log "=== LEVEL ${lid} ==="
	set +e
	"$script" 2>&1 | tee "$logf"
	set -e
	if grep -q '^RESULT=PASS ' "$logf" 2>/dev/null \
		&& ! grep -qE '^RESULT=(FALSE_PASS|PARTIAL) ' "$logf" 2>/dev/null; then
		rescue_log "*** RESCUE PASS at level ${lid} ***"
		echo "RESCUE_PASS level=${lid} log=${RESCUE_LOG_DIR}"
		exit 0
	fi
	rescue_log "level ${lid}: no strict PASS"
done < <(resolve_levels)

rescue_log "tree exhausted A→G — no PASS (valuable negative result for upstream)"
exit 1
