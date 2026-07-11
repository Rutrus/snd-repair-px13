#!/usr/bin/env bash
# Phase 8.1: /proc/interrupts snapshot for ACP_PCI_IRQ (auto-detect IRQ line).
#
# Usage:
#   ./scripts/phase8-irq-snapshot.sh pre-suspend
#   ./scripts/phase8-irq-snapshot.sh post-resume
#   ./scripts/phase8-irq-snapshot.sh compare   # latest pre vs post in validation/.state
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

STATE="${REPO_ROOT}/validation/.state"
mkdir -p "$STATE"

detect_acp_irq() {
	local irq="" line

	if [[ -n "${PHASE8_IRQ:-}" ]]; then
		echo "$PHASE8_IRQ"
		return 0
	fi

	line="$(grep -E 'ACP_PCI_IRQ' /proc/interrupts 2>/dev/null | head -1 || true)"
	if [[ -n "$line" ]]; then
		irq="$(echo "$line" | awk -F: '{print $1}' | tr -d '[:space:]')"
	fi
	if [[ -z "$irq" ]] && command -v journalctl &>/dev/null; then
		irq="$(journalctl -k -b 0 --no-pager 2>/dev/null |
			grep -E 'fn=request_irq irq=' |
			tail -1 |
			sed -n 's/.*fn=request_irq irq=\([0-9]*\).*/\1/p' || true)"
	fi
	[[ -n "$irq" ]] || { echo "Cannot detect ACP PCI IRQ (set PHASE8_IRQ=)" >&2; return 1; }
	echo "$irq"
}

irq_desc_snapshot() {
	local irq="$1"
	local f

	for f in spurious smp_affinity effective_affinity; do
		echo "# /proc/irq/${irq}/${f}:"
		cat "/proc/irq/${irq}/${f}" 2>/dev/null || echo "(missing)"
	done
	if [[ -d "/sys/kernel/irq/${irq}" ]]; then
		for f in actions name chip_name hwirq type wakeup per_cpu_count; do
			echo "# /sys/kernel/irq/${irq}/${f}:"
			cat "/sys/kernel/irq/${irq}/${f}" 2>/dev/null || echo "(missing)"
		done
	else
		echo "# /sys/kernel/irq/${irq}: (missing)"
	fi
}

snapshot() {
	local label="$1"
	local irq
	irq="$(detect_acp_irq)"
	local out="${STATE}/irq-${label}-$(date +%Y%m%dT%H%M%S).txt"

	{
		echo "# $(date -Is) label=${label} irq=${irq} boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
		echo "# full /proc/interrupts:"
		cat /proc/interrupts
		echo "# ---"
		echo "# grep IRQ ${irq} (ACP_PCI_IRQ):"
		grep -E "^[[:space:]]*${irq}:" /proc/interrupts || echo "(no line for IRQ ${irq})"
		echo "# ---"
		echo "# Linux IRQ descriptor (proc + sysfs):"
		irq_desc_snapshot "$irq"
	} >"$out"

	echo "$out"
	grep -E "^[[:space:]]*${irq}:" /proc/interrupts || true
}

compare_latest() {
	local pre post irq_pre irq_post sum_pre sum_post

	pre="$(ls -t "$STATE"/irq-pre-suspend-*.txt 2>/dev/null | head -1 || true)"
	post="$(ls -t "$STATE"/irq-post-resume-*.txt 2>/dev/null | head -1 || true)"
	[[ -n "$pre" && -n "$post" ]] || {
		echo "Need pre-suspend and post-resume snapshots in $STATE" >&2
		exit 1
	}

	irq_pre="$(grep '^# grep IRQ' "$pre" | sed 's/.*IRQ //;s/ (.*//')"
	irq_post="$(grep '^# grep IRQ' "$post" | sed 's/.*IRQ //;s/ (.*//')"
	sum_pre="$(grep -E "^[[:space:]]*${irq_pre}:" "$pre" | awk '{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) s+=$i} END{print s+0}')"
	sum_post="$(grep -E "^[[:space:]]*${irq_post}:" "$post" | awk '{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) s+=$i} END{print s+0}')"

	echo "pre:  $pre"
	echo "post: $post"
	echo "IRQ:  pre=${irq_pre} post=${irq_post}"
	echo "sum:  pre=${sum_pre} post=${sum_post} delta=$((sum_post - sum_pre))"
}

case "${1:-snapshot}" in
pre-suspend) snapshot pre-suspend ;;
post-resume) snapshot post-resume ;;
compare) compare_latest ;;
*)
	echo "Usage: $0 pre-suspend|post-resume|compare" >&2
	exit 1
	;;
esac
