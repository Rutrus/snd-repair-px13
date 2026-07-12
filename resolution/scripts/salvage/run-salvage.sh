#!/usr/bin/env bash
# Salvage runner — topology → destructive → sequence.
# Usage:
#   sudo run-salvage.sh --topology
#   sudo run-salvage.sh --audit
#   sudo run-salvage.sh --restore
#   sudo run-salvage.sh --from-s2 [--campaign SALVAGE-DESTRUCTIVE] [--strategy SD10]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

FROM_S2=0
STRATEGY=""
CAMPAIGN=""
AUDIT=0
RESTORE=0
TOPOLOGY=0
LIST=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--from-s2) FROM_S2=1 ;;
	--strategy | --step) STRATEGY="${2:?}"; shift ;;
	--campaign) CAMPAIGN="${2:?}"; shift ;;
	--audit) AUDIT=1 ;;
	--restore) RESTORE=1 ;;
	--topology) TOPOLOGY=1 ;;
	--list) LIST=1 ;;
	-h | --help)
		cat <<EOF
Usage: sudo $0 [options]
  --topology   discover live kernel tree (ST01)
  --audit        framework audit (read-only)
  --restore      reload boot audio
  --from-s2      require S2 before destructive steps
  --campaign     SALVAGE-TOPOLOGY | SALVAGE-DESTRUCTIVE | SALVAGE-SEQUENCE
  --strategy     one step only (ST01, SD10, S120, ...)
  --list         show campaigns and strategies
EOF
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
	shift
done

require_root "$0"
salvage_ensure_logdir

if [[ "$AUDIT" == "1" ]]; then
	exec "${SCRIPT_DIR}/audit-framework.sh"
fi
if [[ "$RESTORE" == "1" ]]; then
	exec "${SCRIPT_DIR}/restore-boot-audio.sh"
fi
if [[ "$TOPOLOGY" == "1" ]]; then
	exec "${SCRIPT_DIR}/discover-topology.sh"
fi

INDEX="${REPO}/resolution/salvage/strategies.yaml"
[[ -f "$INDEX" ]] || { echo "missing $INDEX" >&2; exit 1; }

resolve_scripts() {
	python3 - "$INDEX" "$CAMPAIGN" "$STRATEGY" <<'PY'
import sys, yaml
idx, camp, strat = sys.argv[1], sys.argv[2], sys.argv[3]
with open(idx) as f:
    d = yaml.safe_load(f)
strat_map = d["strategies"]
campaigns = d.get("campaigns", {})
out = []
if strat:
    s = strat_map.get(strat)
    if s:
        out.append((strat, s["script"]))
elif camp:
    c = campaigns.get(camp, {})
    for sid in c.get("strategies", []):
        out.append((sid, strat_map[sid]["script"]))
else:
    for entry in d.get("default_order", []):
        if entry in campaigns:
            for sid in campaigns[entry].get("strategies", []):
                out.append((sid, strat_map[sid]["script"]))
        elif entry in strat_map:
            out.append((entry, strat_map[entry]["script"]))
for sid, scr in out:
    print(f"{sid}\t{scr}")
PY
}

if [[ "$LIST" == "1" ]]; then
	echo "Campaigns:"
	python3 - "$INDEX" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f)
for cid, c in d.get("campaigns", {}).items():
    print(f"  {cid}: {c.get('strategies', [])}")
PY
	resolve_scripts
	exit 0
fi

if [[ "$FROM_S2" == "1" ]]; then
	salvage_log "certifying S2 entry"
	bf_certify_s2_entry || {
		salvage_log "abort: not in S2 — run restore-boot-audio.sh then s2-reproduce.sh"
		exit 2
	}
fi

salvage_log "log dir: ${SALVAGE_LOG_DIR}"

while IFS=$'\t' read -r sid scr; do
	# ST01 topology runs without S2 gate
	if [[ "$FROM_S2" == "1" && "$sid" != "ST01" ]] && ! bf_require_s2_before_strategy; then
		salvage_log "skip ${sid}: no longer in S2"
		continue
	fi
	script="${SCRIPT_DIR}/strategies/${scr}"
	[[ -x "$script" ]] || chmod +x "$script"
	logf="${SALVAGE_LOG_DIR}/$(date +%Y%m%dT%H%M%S)-${sid}.log"
	salvage_log "=== ${sid} ==="
	set +e
	"$script" 2>&1 | tee "$logf"
	set -e
	if grep -q '^RESULT=PASS ' "$logf" 2>/dev/null \
		&& ! grep -qE '^RESULT=(FALSE_PASS|PARTIAL) ' "$logf" 2>/dev/null; then
		salvage_log "*** SALVAGE PASS ${sid} ***"
		echo "SALVAGE_PASS strategy=${sid} log=${SALVAGE_LOG_DIR}"
		exit 0
	fi
	salvage_log "${sid}: no strict PASS — next"
done < <(resolve_scripts)

salvage_log "salvage exhausted — no PASS"
exit 1
