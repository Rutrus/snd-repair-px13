#!/usr/bin/env bash
# Run ONE edge recovery + Recovery Signature + structured report.
# Usage: sudo ./run-recovery.sh R09
# Consolidation: sudo EDGE_FULL_SIGNATURE=1 ./run-recovery.sh R09
set -euo pipefail

ID="${1:-}"
NOT_EXECUTABLE=0
[[ "${2:-}" == "--not-executable" ]] && NOT_EXECUTABLE=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
STATE="${REPO}/resolution/edges/state.json"

usage() {
	cat <<EOF
Usage: sudo $0 R09

Exploration: one PASS → next edge (no repeat). See EDGE-FRAMEWORK.md
Consolidation: EDGE_FULL_SIGNATURE=1 + phase=consolidation in state.json
EOF
}

[[ -n "$ID" ]] || { usage; exit 1; }

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=edge-metadata.sh
source "$SCRIPT_DIR/edge-metadata.sh" "$ID"

PHASE=$(python3 -c "import json; print(json.load(open('$STATE')).get('phase','exploration'))" 2>/dev/null || echo exploration)

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
R04_MOMENTS_FILE=""
R09_MOMENTS_FILE=""
[[ "$ID" == "R04" ]] && R04_MOMENTS_FILE="$(mktemp)"
[[ "$ID" == "R09" ]] && R09_MOMENTS_FILE="$(mktemp)"
export RESOLUTION_ORCHESTRATED=1 RESOLUTION_WITNESS_FILE="$WITNESS_FILE"
export RESOLUTION_R04_MOMENTS_FILE="${R04_MOMENTS_FILE:-}"
export RESOLUTION_R09_MOMENTS_FILE="${R09_MOMENTS_FILE:-}"
R07_OBS_FILE=""
[[ "$ID" == "R07" ]] && R07_OBS_FILE="$(mktemp)"
export RESOLUTION_R07_OBS_FILE="${R07_OBS_FILE:-}"

echo "[run-recovery] phase=$PHASE edge=${RESOLUTION_EDGE} action=$ID"

WITNESS_VALID="${RESOLUTION_WITNESS_VALID:-1}"
WITNESS_QUALITY="${RESOLUTION_WITNESS_QUALITY:-?}"
WITNESS_REASON="${RESOLUTION_WITNESS_REASON:-not assessed}"
if [[ "$NOT_EXECUTABLE" == "1" ]]; then
	WITNESS_VALID=0
	[[ "$WITNESS_QUALITY" == "?" ]] && WITNESS_QUALITY=W0
fi

if [[ "$NOT_EXECUTABLE" == "1" || "$WITNESS_VALID" == "0" ]]; then
	log "witness gate: INVALID (${WITNESS_QUALITY}) — recovery NOT_EXECUTABLE"
	action_rc=0
elif [[ "${SKIP_RECOVERY_ACTION:-0}" == "1" ]]; then
	log "SKIP_RECOVERY_ACTION=1 — witness only"
	action_rc=0
else
	set +e
	"$action"
	action_rc=$?
	set -e
fi

if [[ -n "$R04_MOMENTS_FILE" && -f "$R04_MOMENTS_FILE" ]]; then
	# shellcheck disable=SC1090
	source "$R04_MOMENTS_FILE"
	rm -f "$R04_MOMENTS_FILE"
fi
if [[ -n "$R09_MOMENTS_FILE" && -f "$R09_MOMENTS_FILE" ]]; then
	# shellcheck disable=SC1090
	source "$R09_MOMENTS_FILE"
	rm -f "$R09_MOMENTS_FILE"
fi
if [[ -n "$R07_OBS_FILE" && -f "$R07_OBS_FILE" ]]; then
	# shellcheck disable=SC1090
	source "$R07_OBS_FILE"
	rm -f "$R07_OBS_FILE"
fi

# FW async download after PCI reset / runtime cycle
if [[ "$NOT_EXECUTABLE" != "1" && "$WITNESS_VALID" == "1" ]]; then
if [[ "$ID" == "R07" || "$ID" == "R08" ]]; then
	wait_fw_settle
fi
fi

witness_args=()
[[ "${EDGE_FULL_SIGNATURE:-0}" == "1" || "$PHASE" == "consolidation" ]] && witness_args+=(--full)
set +e
if [[ "$NOT_EXECUTABLE" == "1" || "$WITNESS_VALID" == "0" ]]; then
	witness_rc=3
	s1=skip s2=skip s3=skip s4=skip s5=skip
	sig_pass=0 sig_total=4
	full_ok=0 partial_ok=0
else
	"$SCRIPT_DIR/witness-signature.sh" "${witness_args[@]}"
	witness_rc=$?
fi
set -e

# shellcheck disable=SC1090
source "$WITNESS_FILE" 2>/dev/null || true
rm -f "$WITNESS_FILE"

# Primary verdict (exploration): ALSA plughw only. Signature S1–S4 = observations.
ALSA_VERDICT=skip
SUSPEND_ONCE=skip
R04_MOMENTS="—"
R09_MOMENTS="—"
R07_OBS="—"

if [[ "$NOT_EXECUTABLE" != "1" && "$WITNESS_VALID" == "1" ]]; then
	if witness_playback_alsa; then
		ALSA_VERDICT=pass
	else
		ALSA_VERDICT=fail
	fi
	if [[ "$ID" == "R04" ]]; then
		R04_MOMENTS="M1=${RESOLUTION_R04_M1:-?} M2=${RESOLUTION_R04_M2:-?} M3=${RESOLUTION_R04_M3:-?}"
	fi
	if [[ "$ID" == "R09" ]]; then
		R09_MOMENTS="D1=${RESOLUTION_R09_D1:-?} D2=${RESOLUTION_R09_D2:-?}"
	fi
	if [[ "$ID" == "R07" ]]; then
		R07_OBS="pci=${RESOLUTION_R07_PCI:-?} | pm: ${RESOLUTION_R07_RT_BEFORE:-?} → ${RESOLUTION_R07_RT_AFTER:-?} | dstate: ${RESOLUTION_R07_PCI_DSTATE_BEFORE:-?} → ${RESOLUTION_R07_PCI_DSTATE_AFTER:-?} | status: ${RESOLUTION_R07_PCI_STATUS_BEFORE:-?} → ${RESOLUTION_R07_PCI_STATUS_AFTER:-?} | iommu_since=${RESOLUTION_R07_IOMMU_FAULTS:-?}"
		if [[ "${RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED:-0}" == "1" ]]; then
			R07_OBS="${R07_OBS} | diff=RELEVANT_UNCHANGED"
		elif [[ "${RESOLUTION_R07_DIFF_RELEVANT_CHANGED:-0}" == "1" ]]; then
			R07_OBS="${R07_OBS} | diff=RELEVANT_CHANGED"
		elif [[ "${RESOLUTION_R07_DIFF_CAPTURED:-0}" == "1" ]]; then
			R07_OBS="${R07_OBS} | diff=CAPTURED"
		else
			R07_OBS="${R07_OBS} | diff=NOT_CAPTURED"
		fi
	fi
fi

RESULT=FAIL
OUTCOME=fail
TRANSITION="S2 → S2"
WITNESS_STATUS=VALID
DOMAIN_STATUS=complete

if [[ "$ID" == "R09" && "${RESOLUTION_R09_D1:-}" != "suspended" ]]; then
	DOMAIN_STATUS=incomplete
fi

if [[ "$NOT_EXECUTABLE" == "1" || "$WITNESS_VALID" == "0" ]]; then
	RESULT=NOT_EXECUTABLE
	OUTCOME=not_executable
	TRANSITION="S? → ? (witness invalid)"
	WITNESS_STATUS=INVALID
	elif [[ "$DOMAIN_STATUS" == "incomplete" ]]; then
	RESULT=BLOCKED
	OUTCOME=blocked
	TRANSITION="S2 → ? (domain blocked — transition not executed)"
	CONF_READ=$("$SCRIPT_DIR/update-confidence.sh" "$RESOLUTION_EDGE" blocked)
elif [[ "$ALSA_VERDICT" == pass ]]; then
	RESULT=PASS
	TRANSITION="S2 → S3"
	if [[ "$PHASE" == "consolidation" ]]; then
		OUTCOME=consolidation
		CONF_READ=$("$SCRIPT_DIR/update-confidence.sh" "$RESOLUTION_EDGE" consolidation)
	else
		OUTCOME=full
		CONF_READ=$("$SCRIPT_DIR/update-confidence.sh" "$RESOLUTION_EDGE" full)
	fi
	# One suspend after PASS: does recovery stick across suspend?
	if [[ "${RESOLUTION_SUSPEND_ONCE:-1}" == "1" ]]; then
		log "post-PASS: suspend once — is system suspendible again?"
		sleep 5
		systemctl suspend
		wait_post_resume_settle
		export RESOLUTION_ASSUME_SUSPEND=1
		if witness_playback_alsa; then
			SUSPEND_ONCE=pass
			log "post-PASS suspend: ALSA still OK"
		else
			SUSPEND_ONCE=fail
			log "post-PASS suspend: ALSA broken again"
		fi
	fi
else
	RESULT=FAIL
	OUTCOME=fail
	TRANSITION="S2 → S2"
	CONF_READ=$("$SCRIPT_DIR/update-confidence.sh" "$RESOLUTION_EDGE" fail)
fi

if [[ "$RESULT" == "NOT_EXECUTABLE" ]]; then
	CONF_READ="skipped (invalid witness)"
	NEXT="s2-reproduce.sh — certify S2 before re-running edges"
	RESEARCH_HINT="—"
elif [[ "$RESULT" == "BLOCKED" ]]; then
	CONF_READ="${CONF_READ:-domain blocked}"
	NEXT_EDGE="${RESOLUTION_NEXT_FAIL:-E07}"
	NEXT_R=$(python3 -c "
import json
e=json.load(open('$STATE'))['edges'].get('$NEXT_EDGE',{})
print(e.get('recovery_id','?'))
" 2>/dev/null || echo "?")
	NEXT="explore ${NEXT_EDGE} (${NEXT_R}) — E09 stays BLOCKED; run I01"
	RESEARCH_HINT="I01: inspectors/I01-runtime-pm-blockers.sh"
else
	# Next candidate (exploration-first)
	NEXT=$("$SCRIPT_DIR/next-edge.sh" "$RESOLUTION_EDGE" 2>/dev/null || echo "?")

	if [[ "$RESULT" == "PASS" ]]; then
		if [[ "$PHASE" == "exploration" && "$NEXT" != "CONSOLIDATION" && "$NEXT" != "DONE" ]]; then
			NEXT_R=$(python3 -c "
import json
e=json.load(open('$STATE'))['edges']['$NEXT']
print(e.get('recovery_id','?'))
" 2>/dev/null || echo "?")
			NEXT="explore ${NEXT} (${NEXT_R}) — do not repeat ${RESOLUTION_EDGE}"
		elif [[ "$NEXT" == "CONSOLIDATION" ]]; then
			python3 -c "
import json
p='$STATE'
d=json.load(open(p))
d['phase']='consolidation'
json.dump(d, open(p,'w'), indent=2)
open(p,'a').write('\n')
" 2>/dev/null || true
			NEXT="CONSOLIDATION sprint — ${RESOLUTION_EDGE} ×3 first"
		elif [[ "$PHASE" == "consolidation" ]]; then
			NEXT="consolidate ${RESOLUTION_EDGE} or $(bash "$SCRIPT_DIR/next-edge.sh")"
		fi
		CONF_F=$(python3 -c "import json; print(json.load(open('$STATE'))['edges']['${RESOLUTION_EDGE}']['confidence'])" 2>/dev/null || echo 0)
		if python3 -c "exit(0 if float('$CONF_F') >= 0.85 else 1)" 2>/dev/null; then
			RESEARCH_HINT="research-ready (≥0.85): ${RESOLUTION_QUESTION}"
		else
			RESEARCH_HINT="—"
		fi
	elif [[ "$RESULT" == "FAIL" ]]; then
		if python3 -c "
import json
e=json.load(open('$STATE'))['edges']['$RESOLUTION_EDGE']
exit(0 if e.get('branch_saturated') else 1)
" 2>/dev/null; then
			NEXT_R=$(python3 -c "
import json
d=json.load(open('$STATE'))
q=d['exploration_queue']
i=q.index('$RESOLUTION_EDGE')+1 if '$RESOLUTION_EDGE' in q else 0
for eid in q[i:]:
 e=d['edges'].get(eid)
 if e and not e.get('branch_saturated') and e.get('status')=='new':
  print(e['recovery_id']); break
" 2>/dev/null || echo "${RESOLUTION_NEXT_FAIL}")
			NEXT="saturated → ${NEXT_R}"
		else
			NEXT="retry ${RESOLUTION_EDGE} or explore $(bash "$SCRIPT_DIR/next-edge.sh")"
		fi
		RESEARCH_HINT="—"
	else
		if [[ "$PHASE" == "exploration" ]]; then
			NEXT_EDGE=$("$SCRIPT_DIR/next-edge.sh" "$RESOLUTION_EDGE" 2>/dev/null || echo "?")
			if [[ "$NEXT_EDGE" == "CONSOLIDATION" ]]; then
				NEXT="CONSOLIDATION sprint"
			elif [[ "$NEXT_EDGE" != "DONE" && "$NEXT_EDGE" != "?" ]]; then
				NEXT_R=$(python3 -c "
import json
e=json.load(open('$STATE'))['edges']['$NEXT_EDGE']
print(e.get('recovery_id','?'))
" 2>/dev/null || echo "?")
				NEXT="explore ${NEXT_EDGE} (${NEXT_R})"
			else
				NEXT="DONE or CONSOLIDATION"
			fi
		else
			NEXT="retry ${RESOLUTION_EDGE}"
		fi
		RESEARCH_HINT="—"
	fi
fi

read -r STATUS CONF_F CONSOL CC <<< "$(python3 -c "
import json
e=json.load(open('$STATE'))['edges']['${RESOLUTION_EDGE}']
print(e.get('status','?'), e.get('confidence',0), e.get('consolidation_count',0), '${PHASE}')
" 2>/dev/null || echo "? 0 0 $PHASE")"

SATURATED=$(python3 -c "
import json
e=json.load(open('$STATE'))['edges']['${RESOLUTION_EDGE}']
print('saturated' if e.get('branch_saturated') else 'active')
" 2>/dev/null || echo "active")

KNOWLEDGE_RESULT="—"
CAMPAIGN_HINT="—"
CAMPAIGN_RESULT="—"
C02_GATES="—"

witness_w2_plus=0
case "${WITNESS_QUALITY:-W0}" in
W2 | W3 | W4) witness_w2_plus=1 ;;
esac

if [[ "$ID" == "R07" && "${RESOLUTION_EDGE:-}" == "E07" ]]; then
	c02_g1=fail c02_g2=fail c02_g3=fail c02_g4=fail
	[[ "$witness_w2_plus" == "1" && "$WITNESS_VALID" == "1" ]] && c02_g1=pass
	[[ "${RESOLUTION_R07_PCI:-}" == "ok" ]] && c02_g2=pass
	[[ "${RESOLUTION_R07_DIFF_CAPTURED:-0}" == "1" ]] && c02_g3=pass
	[[ "${RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED:-0}" == "1" ]] && c02_g4=pass
	C02_GATES="G1_s2=${c02_g1} G2_r07=${c02_g2} G3_snap=${c02_g3} G4_relevant=${c02_g4}"

	if [[ "$c02_g1" == pass && "$c02_g2" == pass && "$c02_g3" == pass && "$c02_g4" == pass \
		&& "$ALSA_VERDICT" == fail ]]; then
		CAMPAIGN_RESULT="C02 KILLED"
		KNOWLEDGE_RESULT=SUCCESS
		CAMPAIGN_HINT="PCI unbind/bind does not modify relevant failure state — missing transition not rebuilt by reprobe"
	elif [[ "$c02_g3" != pass ]]; then
		CAMPAIGN_RESULT="C02 CONVERGING"
		KNOWLEDGE_RESULT=PARTIAL
		CAMPAIGN_HINT="G3 pending — valid BEFORE/AFTER snapshot required"
	elif [[ "${RESOLUTION_R07_DIFF_RELEVANT_CHANGED:-0}" == "1" ]]; then
		CAMPAIGN_RESULT="C02 CONVERGING"
		KNOWLEDGE_RESULT=ADVANCED
		CAMPAIGN_HINT="Relevant register changed — add F014+ to facts.yaml before kill decision"
	elif [[ "$c02_g4" == pass ]]; then
		CAMPAIGN_RESULT="C02 CONVERGING"
		KNOWLEDGE_RESULT=SUCCESS
		CAMPAIGN_HINT="G4 pass — confirm all gates on next line if ALSA still fail"
	fi
elif [[ "$NOT_EXECUTABLE" != "1" && "$WITNESS_VALID" == "1" ]]; then
	if [[ "$RESULT" == "PASS" ]]; then
		KNOWLEDGE_RESULT=SUCCESS
	elif [[ "$RESULT" == "BLOCKED" ]]; then
		KNOWLEDGE_RESULT=ADVANCED
		CAMPAIGN_HINT="domain blocked — transition not executed"
	elif [[ "$RESULT" == "FAIL" && "$DOMAIN_STATUS" == "complete" ]]; then
		KNOWLEDGE_RESULT=ADVANCED
	elif [[ "$RESULT" == "FAIL" ]]; then
		KNOWLEDGE_RESULT=PARTIAL
	fi
fi

cat <<EOF

=== RESOLUTION EDGE REPORT ===
Phase:             ${CC}
Witness:           ${WITNESS_STATUS} (${WITNESS_QUALITY})
Witness Detail:    ${WITNESS_REASON}
Edge:              ${RESOLUTION_EDGE}
Recovery:          ${ID}
Edge Result:       ${RESULT} (recovery / ALSA)
Knowledge Result:  ${KNOWLEDGE_RESULT}
Campaign Result:   ${CAMPAIGN_RESULT}
C02 Kill Gates:    ${C02_GATES}
Campaign Hint:     ${CAMPAIGN_HINT}
Status:            ${STATUS}
Confidence:        ${CONF_F} (dynamic)
Transition:        ${TRANSITION}
Recovery Domain:   ${RESOLUTION_DOMAIN:-?}
Domain Status:     ${DOMAIN_STATUS}
Recovery Cost:     ${RESOLUTION_COST}
Knowledge Gain:    ${RESOLUTION_KNOW}
ALSA Verdict:      ${ALSA_VERDICT} (primary PASS/FAIL)
Observations:      ${sig_pass:-?}/${sig_total:-4} (S1=${s1:-?} S2=${s2:-?} S3=${s3:-?} S4=${s4:-?} S5=${s5:-?})
R04 Moments:       ${R04_MOMENTS}
R09 Domain:        ${R09_MOMENTS}
R07 Differential:  ${R07_OBS}
Suspend Once:      ${SUSPEND_ONCE} (post-PASS only)
Unlocked Question: ${RESOLUTION_QUESTION}
Research Gate:     ${RESEARCH_HINT:-—}
Next Candidate:    ${NEXT}
Branch Status:     ${SATURATED}
==============================
EOF

echo "Log → resolution/TRACKER.md · resolution/edges/${RESOLUTION_EDGE}.md"

if [[ "$RESULT" == "NOT_EXECUTABLE" ]]; then exit 3; fi
if [[ "$RESULT" == "BLOCKED" ]]; then exit 4; fi
if [[ "$RESULT" == "PASS" ]]; then exit 0; fi
if [[ "$RESULT" == "PARTIAL" ]]; then exit 2; fi
exit 1
