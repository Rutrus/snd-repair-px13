#!/usr/bin/env bash
# R07 — Layer 4: PCI driver unbind + bind (ACP) — full PCI reprobe.
# PASS/FAIL = ALSA only; differential evidence snapshot before/after.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=../inspectors/_evidence-snapshot.sh
source "$SCRIPT_DIR/../inspectors/_evidence-snapshot.sh"

require_root "$0"
ACTION_SINCE="$(date -Iseconds)"

log "R07: PCI unbind+bind $PCI_DEV (L4) — differential snapshot"
section() { log "R07-${1}"; }

section "snapshot BEFORE"
evidence_snapshot_log "before"

TMP_SNAP="$(mktemp)"
evidence_snapshot_emit BEFORE >"$TMP_SNAP"
# shellcheck disable=SC1090
source "$TMP_SNAP"

stop_pipewire_all
if pci_reset_acp; then
	log "R07: pci_reset OK"
	export RESOLUTION_R07_PCI=ok
else
	log "R07: pci_reset FAILED"
	export RESOLUTION_R07_PCI=fail
	rm -f "$TMP_SNAP"
	exit 1
fi

sleep 2
section "snapshot AFTER"
evidence_snapshot_log "after"

{
	evidence_snapshot_emit AFTER "$ACTION_SINCE"
} >>"$TMP_SNAP"
# shellcheck disable=SC1090
source "$TMP_SNAP"
rm -f "$TMP_SNAP"

export RESOLUTION_R07_RT_BEFORE="${BEFORE_RUNTIME_PM:-?}"
export RESOLUTION_R07_RT_AFTER="${AFTER_RUNTIME_PM:-?}"
export RESOLUTION_R07_PCI_DSTATE_BEFORE="${BEFORE_PCI_DSTATE:-?}"
export RESOLUTION_R07_PCI_DSTATE_AFTER="${AFTER_PCI_DSTATE:-?}"
export RESOLUTION_R07_PCI_STATUS_BEFORE="${BEFORE_PCI_STATUS:-?}"
export RESOLUTION_R07_PCI_STATUS_AFTER="${AFTER_PCI_STATUS:-?}"
export RESOLUTION_R07_PHASE10_BEFORE="${BEFORE_PHASE10:-?}"
export RESOLUTION_R07_PHASE10_AFTER="${AFTER_PHASE10:-?}"
export RESOLUTION_R07_IOMMU_FAULTS="${AFTER_IOMMU_FAULTS:-0}"

export RESOLUTION_R07_DIFF_CAPTURED=0
export RESOLUTION_R07_DIFF_UNCHANGED=0
export RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED=0
export RESOLUTION_R07_DIFF_RELEVANT_CHANGED=0
if [[ -n "${BEFORE_PCI_STATUS:-}" && -n "${AFTER_PCI_STATUS:-}" \
	&& "${BEFORE_PCI_STATUS}" != "?" && "${AFTER_PCI_STATUS}" != "?" ]]; then
	export RESOLUTION_R07_DIFF_CAPTURED=1
	if [[ "${BEFORE_RUNTIME_PM}" == "${AFTER_RUNTIME_PM}" \
		&& "${BEFORE_PCI_DSTATE}" == "${AFTER_PCI_DSTATE}" \
		&& "${BEFORE_PCI_STATUS}" == "${AFTER_PCI_STATUS}" ]]; then
		export RESOLUTION_R07_DIFF_UNCHANGED=1
	fi
	if evidence_snapshot_relevant_unchanged \
		"${BEFORE_RUNTIME_PM}" "${AFTER_RUNTIME_PM}" \
		"${BEFORE_PCI_DSTATE}" "${AFTER_PCI_DSTATE}" \
		"${BEFORE_PCI_STATUS}" "${AFTER_PCI_STATUS}"; then
		export RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED=1
	else
		export RESOLUTION_R07_DIFF_RELEVANT_CHANGED=1
	fi
fi

log "R07-DIFF runtime_pm: ${RESOLUTION_R07_RT_BEFORE} → ${RESOLUTION_R07_RT_AFTER}"
log "R07-DIFF pci_dstate:  ${RESOLUTION_R07_PCI_DSTATE_BEFORE} → ${RESOLUTION_R07_PCI_DSTATE_AFTER}"
log "R07-DIFF pci_status:  ${RESOLUTION_R07_PCI_STATUS_BEFORE} → ${RESOLUTION_R07_PCI_STATUS_AFTER}"
log "R07-DIFF iommu_faults_since_action=${RESOLUTION_R07_IOMMU_FAULTS}"
if [[ "${RESOLUTION_R07_DIFF_CAPTURED}" == "1" ]]; then
	if [[ "${RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED}" == "1" ]]; then
		log "R07-DIFF verdict: RELEVANT_UNCHANGED (C02 kill gate G4)"
	elif [[ "${RESOLUTION_R07_DIFF_RELEVANT_CHANGED}" == "1" ]]; then
		log "R07-DIFF verdict: RELEVANT_CHANGED — record F014+ before killing C02"
	else
		log "R07-DIFF verdict: captured (review fields)"
	fi
else
	log "R07-DIFF verdict: NOT CAPTURED"
fi

if [[ -n "${RESOLUTION_R07_OBS_FILE:-}" ]]; then
	{
		printf 'RESOLUTION_R07_PCI=%q\n' "${RESOLUTION_R07_PCI:-?}"
		printf 'RESOLUTION_R07_RT_BEFORE=%q\n' "${RESOLUTION_R07_RT_BEFORE:-?}"
		printf 'RESOLUTION_R07_RT_AFTER=%q\n' "${RESOLUTION_R07_RT_AFTER:-?}"
		printf 'RESOLUTION_R07_PCI_DSTATE_BEFORE=%q\n' "${RESOLUTION_R07_PCI_DSTATE_BEFORE:-?}"
		printf 'RESOLUTION_R07_PCI_DSTATE_AFTER=%q\n' "${RESOLUTION_R07_PCI_DSTATE_AFTER:-?}"
		printf 'RESOLUTION_R07_PCI_STATUS_BEFORE=%q\n' "${RESOLUTION_R07_PCI_STATUS_BEFORE:-?}"
		printf 'RESOLUTION_R07_PCI_STATUS_AFTER=%q\n' "${RESOLUTION_R07_PCI_STATUS_AFTER:-?}"
		printf 'RESOLUTION_R07_PHASE10_BEFORE=%q\n' "${RESOLUTION_R07_PHASE10_BEFORE:-?}"
		printf 'RESOLUTION_R07_PHASE10_AFTER=%q\n' "${RESOLUTION_R07_PHASE10_AFTER:-?}"
		printf 'RESOLUTION_R07_IOMMU_FAULTS=%s\n' "${RESOLUTION_R07_IOMMU_FAULTS:-0}"
		printf 'RESOLUTION_R07_DIFF_CAPTURED=%s\n' "${RESOLUTION_R07_DIFF_CAPTURED:-0}"
		printf 'RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED=%s\n' "${RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED:-0}"
		printf 'RESOLUTION_R07_DIFF_RELEVANT_CHANGED=%s\n' "${RESOLUTION_R07_DIFF_RELEVANT_CHANGED:-0}"
	} >"${RESOLUTION_R07_OBS_FILE}"
fi

start_pipewire_all
log "R07 done — question: what changed pre→post? (ALSA PASS/FAIL separate)"
