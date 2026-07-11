#!/usr/bin/env bash
# I02 — AMD-Vi IO_PAGE_FAULT (Timeline inspector).
# Usage: sudo ./I02-iommu-faults.sh [boot|since-last-resume]
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_SCRIPT_DIR}/../recovery/_lib.sh"
# shellcheck source=/dev/null
source "${_SCRIPT_DIR}/_evidence-snapshot.sh"

PCI="${PX13_PCI_DEV:-0000:c4:00.5}"
PCI_BDF="${PCI#0000:}"
MODE="${1:-boot}"
TS="$(date -Iseconds)"

section() { echo ""; echo "=== $* ==="; }

fault_journal() {
	local since="${1:-}"
	local -a cmd=(journalctl -k -b 0 -o short-iso --no-pager)
	[[ -n "$since" ]] && cmd+=(--since "$since")
	"${cmd[@]}" 2>/dev/null \
		| grep -E "AMD-Vi: Event logged \[IO_PAGE_FAULT.*(device=${PCI_BDF}|${PCI})"
}

phase10_journal() {
	local since="${1:-}"
	local -a cmd=(journalctl -k -b 0 -o short-iso --no-pager)
	[[ -n "$since" ]] && cmd+=(--since "$since")
	"${cmd[@]}" 2>/dev/null \
		| grep -E 'PHASE10.*pci_intx when=post_delay.*resume='
}

# Extract fields from IO_PAGE_FAULT bracket payload.
parse_fault_fields() {
	local line="$1"
	local payload domain device pasid address flags
	payload="$(echo "$line" | sed -n 's/.*\[IO_PAGE_FAULT \(.*\)\].*/\1/p')"
	domain="$(echo "$payload" | sed -n 's/.*domain=\(0x[0-9a-fA-F]*\).*/\1/p')"
	device="$(echo "$payload" | sed -n 's/.*device=\([^ ]*\).*/\1/p')"
	pasid="$(echo "$payload" | sed -n 's/.*pasid=\(0x[0-9a-fA-F]*\).*/\1/p')"
	address="$(echo "$payload" | sed -n 's/.*address=\(0x[0-9a-fA-F]*\).*/\1/p')"
	flags="$(echo "$payload" | sed -n 's/.*flags=\(0x[0-9a-fA-F]*\).*/\1/p')"
	[[ -z "$pasid" ]] && pasid="—"
	printf '%s\t%s\t%s\t%s\t%s\t%s' \
		"${domain:-?}" "${device:-?}" "${pasid}" "${address:-?}" "${flags:-?}" "$(flags_perm_hint "${flags:-0x0}")"
}

flags_perm_hint() {
	local flags="${1:-0x0}"
	local n
	n=$((flags))
	if (( n == 0 )); then
		echo "read(non-present)"
	elif (( (n & 0x10) != 0 )); then
		echo "write?"
	else
		printf 'flags=%s' "$flags"
	fi
}

line_epoch() {
	local iso="$1"
	date -d "$iso" +%s.%N 2>/dev/null || date -d "${iso/T/ }" +%s 2>/dev/null || echo 0
}

# Type A: fault before first PHASE10 post_delay in same resume window.
# Type B: fault after PHASE10 post_delay.
# Type C: no PHASE10 anchor in window (independent / boot-only).
classify_fault_timing() {
	local fault_iso="$1"
	local resume_since="$2"
	local stat1_iso stat1_ep fault_ep
	fault_ep="$(line_epoch "$fault_iso")"

	mapfile -t stat_lines < <(phase10_journal "$resume_since" | grep 'resume=1' || true)
	if [[ ${#stat_lines[@]} -eq 0 ]]; then
		echo "C"
		return
	fi
	stat1_iso="$(echo "${stat_lines[0]}" | awk '{print $1}')"
	stat1_ep="$(line_epoch "$stat1_iso")"
	if awk -v f="$fault_ep" -v s="$stat1_ep" 'BEGIN { exit (f < s) ? 0 : 1 }'; then
		echo "A"
	elif awk -v f="$fault_ep" -v s="$stat1_ep" 'BEGIN { exit (f > s) ? 0 : 1 }'; then
		echo "B"
	else
		echo "B"
	fi
}

last_resume_since() {
	journalctl -k -b 0 --no-pager -g 'PM: suspend exit' -o short-iso 2>/dev/null \
		| tail -1 | awk '{print $1}' || true
}

echo "=== I02 IOMMU / IO_PAGE_FAULT ==="
echo "Time:  ${TS}"
echo "PCI:   ${PCI}"
echo "Mode:  ${MODE}"
echo "Evidence: resolution/evidence/facts.yaml (O_IOMMU)"

section "System snapshot (now)"
evidence_snapshot_log "now"

section "Parsed faults (Domain | Device | PASID | Address | Flags | Perm hint | Timing)"
RESUME_SINCE="$(last_resume_since)"
WINDOW_SINCE=""
if [[ -n "$RESUME_SINCE" && "$MODE" != "boot" ]]; then
	WINDOW_SINCE="$RESUME_SINCE"
fi

mapfile -t FAULT_LINES < <(fault_journal "${WINDOW_SINCE}")
if [[ ${#FAULT_LINES[@]} -eq 0 ]]; then
	echo "  (none)"
else
	printf '  %-10s %-12s %-10s %-20s %-12s %-18s %s\n' \
		Domain Device PASID Address Flags Perm Type
	for line in "${FAULT_LINES[@]}"; do
		iso="$(echo "$line" | awk '{print $1}')"
		fields="$(parse_fault_fields "$line")"
		IFS=$'\t' read -r domain device pasid address flags perm <<<"$fields"
		timing="$(classify_fault_timing "$iso" "${RESUME_SINCE:-}")"
		printf '  %-10s %-12s %-10s %-20s %-12s %-18s %s\n' \
			"$domain" "$device" "$pasid" "$address" "$flags" "$perm" "$timing"
	done
	echo ""
	echo "  count: ${#FAULT_LINES[@]}"
	echo "  unique addresses:"
	printf '%s\n' "${FAULT_LINES[@]}" \
		| sed -n 's/.*address=\(0x[0-9a-fA-F]*\).*/\1/p' | sort -u | sed 's/^/    /'
fi

section "Timing classes (vs PHASE10 post_delay resume=1)"
echo "  Type A = fault BEFORE STAT1 witness"
echo "  Type B = fault AFTER STAT1 witness"
echo "  Type C = no PHASE10 anchor in resume window"
if [[ ${#FAULT_LINES[@]} -gt 0 ]]; then
	a=0 b=0 c=0
	for line in "${FAULT_LINES[@]}"; do
		iso="$(echo "$line" | awk '{print $1}')"
		t="$(classify_fault_timing "$iso" "${RESUME_SINCE:-}")"
		case "$t" in A) a=$((a + 1)) ;; B) b=$((b + 1)) ;; *) c=$((c + 1)) ;; esac
	done
	echo "  A=${a} B=${b} C=${c}"
fi

if [[ -n "$RESUME_SINCE" ]]; then
	section "PHASE10 anchor (first post_delay resume=1 since ${RESUME_SINCE})"
	phase10_journal "$RESUME_SINCE" | grep 'resume=1' | head -1 | sed 's/^/  /' || echo "  (none)"
fi

section "PHASE10 post_delay (STAT1/INTx witness, tail)"
phase10_journal | tail -5 | sed 's/^/  /' || echo "  (none)"

section "Evidence graph hooks (observability only — not primary hypothesis)"
echo "  • IO_PAGE_FAULT may be cause, consequence, or co-symptom — see evidence/hypotheses.md"
echo "  • If Type A dominates → DMA/IOMMU before STAT1 latch (competitor H-DMA)"
echo "  • If Type B only → likely downstream of ACP MMIO event"
echo "  • Research FACT 6: fault not necessary for FAIL (0010/0012)"
section "Next"
echo "  Compare boot S0 vs S2; re-run after E07 differential snapshot"
echo "==============================="
