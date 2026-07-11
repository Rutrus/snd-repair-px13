#!/usr/bin/env bash
# Capture /proc/interrupts line for ACP PCI IRQ (PX13: usually 164).
# Usage:
#   ./scripts/phase7-irq-snapshot.sh pre-suspend
#   ./scripts/phase7-irq-snapshot.sh post-resume
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

LABEL="${1:-snapshot}"
IRQ="${PHASE7_IRQ:-164}"
OUT="${REPO_ROOT}/validation/.state/irq-${LABEL}-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p "${REPO_ROOT}/validation/.state"

{
	echo "# $(date -Is) label=${LABEL} irq=${IRQ}"
	echo "# full /proc/interrupts:"
	cat /proc/interrupts
	echo "# ---"
	echo "# grep IRQ ${IRQ}:"
	grep -E "^[[:space:]]*${IRQ}:" /proc/interrupts || echo "(no line for IRQ ${IRQ})"
} >"$OUT"

echo "$OUT"
grep -E "^[[:space:]]*${IRQ}:" /proc/interrupts || true
