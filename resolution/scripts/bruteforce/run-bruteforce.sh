#!/usr/bin/env bash
# Bruteforce recovery runner — try strategies until PASS.
# Usage:
#   sudo run-bruteforce.sh [--from-s2] [--campaign R300] [--strategy S020] [--loop] [--list]
#   sudo run-bruteforce.sh --validate [--phase all|modules|pci|objects|unload]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

FROM_S2=0
LOOP=0
CAMPAIGN=""
STRATEGY=""
LIST=0
VALIDATE=0
VALIDATE_PHASE="all"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--from-s2) FROM_S2=1 ;;
	--loop) LOOP=1 ;;
	--list) LIST=1 ;;
	--validate) VALIDATE=1 ;;
	--phase) VALIDATE_PHASE="${2:?}"; shift ;;
	--campaign) CAMPAIGN="${2:?}"; shift ;;
	--strategy) STRATEGY="${2:?}"; shift ;;
	-h | --help)
		echo "Usage: sudo $0 [--from-s2] [--campaign R300] [--strategy S020] [--loop] [--list]"
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
	shift
done

require_root "$0"
bf_ensure_logdir

if [[ "$VALIDATE" == "1" ]]; then
	exec "${SCRIPT_DIR}/validate/run-validate.sh" --phase "$VALIDATE_PHASE"
fi

INDEX="${REPO}/resolution/bruteforce/strategies.yaml"
[[ -f "$INDEX" ]] || {
	echo "missing $INDEX" >&2
	exit 1
}

mapfile -t DEFAULT_ORDER < <(python3 - "$INDEX" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f)
for c in d.get("default_order", []):
    print(c)
PY
)

run_strategy() {
	local script="$1"
	local sid="$2"
	local logf="${BF_LOG_DIR}/$(date +%Y%m%dT%H%M%S)-${sid}.log"

	if [[ "$FROM_S2" == "1" ]] && ! bf_require_s2_before_strategy; then
		bf_log "=== skip ${sid} (not in S2) ==="
		return 1
	fi

	bf_log "=== running ${sid} ==="
	set +e
	"$script" 2>&1 | tee "$logf"
	local rc=${PIPESTATUS[0]}
	set -e
	# Only strict PASS counts — reject PARTIAL / FALSE_PASS
	if grep -q '^RESULT=PASS ' "$logf" 2>/dev/null \
		&& ! grep -qE '^RESULT=(FALSE_PASS|PARTIAL) ' "$logf" 2>/dev/null; then
		return 0
	fi
	return 1
}

resolve_script_path() {
	local scr="$1"
	if [[ "$scr" == validate/* ]]; then
		echo "${SCRIPT_DIR}/${scr}"
	else
		echo "${SCRIPT_DIR}/strategies/${scr}"
	fi
}

resolve_scripts() {
	python3 - "$INDEX" "$CAMPAIGN" "$STRATEGY" <<'PY'
import sys, yaml
idx, camp, strat = sys.argv[1], sys.argv[2], sys.argv[3]
with open(idx) as f:
    d = yaml.safe_load(f)
strat_map = d["strategies"]
out = []
if strat:
    s = strat_map.get(strat)
    if s:
        out.append((strat, s["script"]))
else:
    camps = [camp] if camp else d.get("default_order", [])
    for c in camps:
        for sid in d["campaigns"].get(c, {}).get("strategies", []):
            out.append((sid, strat_map[sid]["script"]))
for sid, scr in out:
    print(f"{sid}\t{scr}")
PY
}

if [[ "$LIST" == "1" ]]; then
	echo "Campaigns: ${DEFAULT_ORDER[*]}"
	resolve_scripts
	exit 0
fi

if [[ "$FROM_S2" != "1" ]]; then
	bf_log "Reproduce S2 first (or pass --from-s2 if already broken)"
	"${REPO}/resolution/scripts/s2-reproduce.sh" || {
		bf_log "S2 not certified — abort"
		exit 2
	}
else
	bf_log "Certifying S2 entry (--from-s2)"
	bf_certify_s2_entry || {
		bf_log "Abort: not in certifiable S2 — run s2-reproduce.sh first"
		bf_log "note: --validate --phase unload reloads audio and breaks S2"
		exit 2
	}
fi

bf_log "log dir: ${BF_LOG_DIR}"
bf_log "goal: first ALSA PASS — not elegance"

while true; do
	pass=0
	while IFS=$'\t' read -r sid scr; do
		script="$(resolve_script_path "$scr")"
		[[ -x "$script" ]] || chmod +x "$script"
		if run_strategy "$script" "$sid"; then
			bf_log "*** PASS strategy=${sid} — STOP ***"
			echo "BRUTEFORCE_PASS strategy=${sid} log=${BF_LOG_DIR}"
			exit 0
		fi
		bf_log "strategy ${sid} failed — next"
	done < <(resolve_scripts)

	[[ "$LOOP" == "1" ]] || break
	bf_log "loop: all strategies failed — retry in 60s"
	sleep 60
done

bf_log "no PASS in this run"
exit 1
