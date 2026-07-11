#!/usr/bin/env bash
# Run ONE edge recovery + Recovery Signature + structured report.
# Usage: sudo EDGE_FULL_SIGNATURE=1 ./run-recovery.sh R09
set -euo pipefail

ID="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-${HOME}/snd_repair}"

usage() {
	cat <<EOF
Usage: sudo [$0 R09]

Exploration order: R09 → R07 → R08 → R04
Env: EDGE_FULL_SIGNATURE=1  — include S5 suspend #2 in signature

See resolution/EDGE-FRAMEWORK.md
EOF
}

[[ -n "$ID" ]] || { usage; exit 1; }

# shellcheck source=edge-metadata.sh
source "$SCRIPT_DIR/edge-metadata.sh" "$ID"

case "$ID" in
R01) action="${SCRIPT_DIR}/R01-restart-pipewire.sh" ;;
R02) action="${SCRIPT_DIR}/R02-alsa-reload.sh" ;;
R03) action="${SCRIPT_DIR}/R03-unbind-rt721.sh" ;;
R04) action="${SCRIPT_DIR}/R04-rebind-manager.sh" ;;
R05) action="${SCRIPT_DIR}/R05-sdw-rescan.sh" ;;
R06) action="${SCRIPT_DIR}/R06-reload-acp-module.sh" ;;
R07) action="${SCRIPT_DIR}/R07-rebind-pci.sh" ;;
R08) action="${SCRIPT_DIR}/R08-remove-rescan-pci.sh" ;;
R09) action="${SCRIPT_DIR}/R09-runtime-pm-cycle.sh" ;;
R10) action="${SCRIPT_DIR}/R10-secondary-suspend.sh" ;;
*) echo "unknown ID: $ID" >&2; usage; exit 1 ;;
esac

[[ -x "$action" ]] || { echo "missing: $action" >&2; exit 1; }

WITNESS_FILE="$(mktemp)"
export RESOLUTION_ORCHESTRATED=1 RESOLUTION_WITNESS_FILE="$WITNESS_FILE"

echo "[run-recovery] Edge ${RESOLUTION_EDGE} — action $ID"
set +e
"$action"
action_rc=$?
set -e

witness_args=()
[[ "${EDGE_FULL_SIGNATURE:-0}" == "1" ]] && witness_args+=(--full)
set +e
"$SCRIPT_DIR/witness-signature.sh" "${witness_args[@]}"
witness_rc=$?
set -e

# shellcheck disable=SC1090
source "$WITNESS_FILE" 2>/dev/null || true
rm -f "$WITNESS_FILE"

RESULT=FAIL
OUTCOME=fail
TRANSITION="S2 → S2"
NEXT="${RESOLUTION_EDGE} (repeat)"

if [[ "${full_ok:-0}" == "1" ]]; then
	RESULT=PASS
	OUTCOME=full
	TRANSITION="S2 → S3"
	CONF_READ=$("$SCRIPT_DIR/update-confidence.sh" "$RESOLUTION_EDGE" full)
	if echo "$CONF_READ" | grep -q 'status=stable'; then
		NEXT="RESEARCH — ${RESOLUTION_QUESTION}"
	else
		NEXT="${RESOLUTION_EDGE} (repeat to 5/5)"
	fi
elif [[ "${partial_ok:-0}" == "1" || "$witness_rc" -eq 2 ]]; then
	RESULT=PARTIAL
	OUTCOME=partial
	TRANSITION="S2 → S3?"
	NEXT="${RESOLUTION_EDGE} (repeat with EDGE_FULL_SIGNATURE=1)"
	"$SCRIPT_DIR/update-confidence.sh" "$RESOLUTION_EDGE" partial >/dev/null || true
else
	OUTCOME=fail
	CONF_READ=$("$SCRIPT_DIR/update-confidence.sh" "$RESOLUTION_EDGE" fail)
	STATE="${REPO}/resolution/edges/state.json"
	if python3 -c "
import json
e=json.load(open('$STATE'))['edges']['$RESOLUTION_EDGE']
exit(0 if e.get('branch_saturated') else 1)
" 2>/dev/null; then
		NEXT="${RESOLUTION_NEXT_FAIL} (branch saturated)"
	else
		NEXT="${RESOLUTION_EDGE} (retry) or ${RESOLUTION_NEXT_FAIL}"
	fi
fi

CONF_LINE=$(python3 -c "
import json
e=json.load(open('${REPO}/resolution/edges/state.json'))['edges']['${RESOLUTION_EDGE}']
print(f\"{e['confidence']}/{e['max_confidence']}\")
" 2>/dev/null || echo "?/5")

SATURATED=$(python3 -c "
import json
e=json.load(open('${REPO}/resolution/edges/state.json'))['edges']['${RESOLUTION_EDGE}']
print('saturated' if e.get('branch_saturated') else 'active')
" 2>/dev/null || echo "active")

cat <<EOF

=== RESOLUTION EDGE REPORT ===
Edge:              ${RESOLUTION_EDGE}
Recovery:          ${ID}
Result:            ${RESULT}
Confidence:        ${CONF_LINE}
Recovered Layer:   ${RESOLUTION_LAYER}
Transition:        ${TRANSITION}
Recovery Cost:     ${RESOLUTION_COST}
Knowledge Gain:    ${RESOLUTION_KNOW}
Signature:         ${sig_pass:-?}/${sig_total:-4} (S1=${s1:-?} S2=${s2:-?} S3=${s3:-?} S4=${s4:-?} S5=${s5:-?})
Unlocked Question: ${RESOLUTION_QUESTION}
Next Candidate:    ${NEXT}
Branch Status:     ${SATURATED}
Action RC:         ${action_rc}  Witness RC: ${witness_rc}
==============================
EOF

# Log hint
echo "Update: resolution/edges/${RESOLUTION_EDGE}.md confidence log + TRACKER.md"

if [[ "$RESULT" == "PASS" ]]; then exit 0; fi
if [[ "$RESULT" == "PARTIAL" ]]; then exit 2; fi
exit 1
