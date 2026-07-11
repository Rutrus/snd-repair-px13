#!/usr/bin/env bash
# Read-only system snapshots for evidence graph / differential edges (I02, R07).
# shellcheck disable=SC2034
PCI_DEV="${PX13_PCI_DEV:-0000:c4:00.5}"
PCI_BDF="${PCI_DEV#0000:}"

_evidence_setpci_word() {
	local reg="$1"
	command -v setpci >/dev/null 2>&1 || {
		echo "?"
		return
	}
	setpci -s "$PCI_BDF" "${reg}.W" 2>/dev/null || echo "?"
}

# PCI_STATUS word + INTx bit (bit 3 of status register).
evidence_pci_status() {
	local w dec intx
	w="$(_evidence_setpci_word 04)"
	[[ "$w" == "?" ]] && {
		echo "?"
		return
	}
	dec=$((16#$w))
	intx=$(( (dec >> 3) & 1 ))
	printf '0x%04x intx_status=%d' "$dec" "$intx"
}

# PMCSR D-state (bits 1:0).
evidence_pci_dstate() {
	local w dec d
	w="$(_evidence_setpci_word F4)"
	[[ "$w" == "?" ]] && {
		echo "?"
		return
	}
	dec=$((16#$w))
	d=$(( dec & 3 ))
	printf 'PMCSR=0x%04x D%d' "$dec" "$d"
}

evidence_runtime_pm() {
	local sys="/sys/bus/pci/devices/${PCI_DEV}/power"
	printf 'runtime_status=%s runtime_usage=%s' \
		"$(cat "${sys}/runtime_status" 2>/dev/null || echo ?)" \
		"$(cat "${sys}/runtime_usage" 2>/dev/null || echo ?)"
}

evidence_phase10_latest() {
	journalctl -k -b 0 --no-pager 2>/dev/null \
		| grep -E 'PHASE10.*pci_intx when=post_delay' \
		| tail -1 | sed 's/^[^ ]* [^ ]* [^ ]* //' || echo "(none)"
}

evidence_iommu_fault_count() {
	local since="${1:-}"
	local -a cmd=(journalctl -k -b 0 --no-pager)
	[[ -n "$since" ]] && cmd+=(--since "$since")
	"${cmd[@]}" 2>/dev/null \
		| grep -cE "AMD-Vi: Event logged \[IO_PAGE_FAULT.*(device=${PCI_BDF}|${PCI_DEV})" || true
}

# Emit KEY=value lines safe for shell source (all string values %q-quoted).
evidence_snapshot_emit() {
	local prefix="$1"
	local since="${2:-}"
	printf '%s_RUNTIME_PM=%q\n' "$prefix" "$(evidence_runtime_pm)"
	printf '%s_PCI_DSTATE=%q\n' "$prefix" "$(evidence_pci_dstate)"
	printf '%s_PCI_STATUS=%q\n' "$prefix" "$(evidence_pci_status)"
	printf '%s_PHASE10=%q\n' "$prefix" "$(evidence_phase10_latest)"
	if [[ -n "$since" ]]; then
		printf '%s_IOMMU_FAULTS=%s\n' "$prefix" "$(evidence_iommu_fault_count "$since")"
	else
		printf '%s_IOMMU_FAULTS_BOOT=%s\n' "$prefix" "$(evidence_iommu_fault_count "")"
	fi
}

# True if relevant snapshot fields unchanged (C02 kill gate G4).
# Compares: runtime_pm, pci_dstate, pci_status register word (not PHASE10 journal).
evidence_pci_status_word() {
	local w
	w="$(_evidence_setpci_word 04)"
	[[ "$w" == "?" ]] && {
		echo "?"
		return
	}
	printf '0x%04x' $((16#$w))
}

evidence_snapshot_relevant_unchanged() {
	local b_pm="$1" a_pm="$2" b_ds="$3" a_ds="$4" b_st="$5" a_st="$6"
	local b_word a_word
	b_word="$(echo "$b_st" | sed -n 's/^\(0x[0-9a-fA-F]*\).*/\1/p')"
	a_word="$(echo "$a_st" | sed -n 's/^\(0x[0-9a-fA-F]*\).*/\1/p')"
	[[ -z "$b_word" ]] && b_word="$b_st"
	[[ -z "$a_word" ]] && a_word="$a_st"
	[[ "$b_pm" == "$a_pm" && "$b_ds" == "$a_ds" && "$b_word" == "$a_word" && "$b_word" != "?" ]]
}

evidence_snapshot_diff_summary() {
	local b_pm="$1" a_pm="$2" b_ds="$3" a_ds="$4" b_st="$5" a_st="$6"
	echo "runtime_pm: ${b_pm} → ${a_pm}"
	echo "pci_dstate: ${b_ds} → ${a_ds}"
	echo "pci_status: ${b_st} → ${a_st}"
}

evidence_snapshot_log() {
	local label="$1"
	echo "  ${label} runtime_pm: $(evidence_runtime_pm)"
	echo "  ${label} pci_dstate: $(evidence_pci_dstate)"
	echo "  ${label} pci_status: $(evidence_pci_status)"
	echo "  ${label} phase10:    $(evidence_phase10_latest)"
}
