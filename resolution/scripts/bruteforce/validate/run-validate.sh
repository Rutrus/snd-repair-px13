#!/usr/bin/env bash
# Validate bruteforce actions actually occur (before asking "does it recover?").
# Usage: sudo run-validate.sh [--phase all|modules|pci|objects|holders|unload]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../_lib.sh
source "${BF_DIR}/_lib.sh"

PHASE="all"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--phase) PHASE="${2:?}"; shift 2 ;;
	--help | -h)
		echo "Usage: sudo $0 [--phase all|modules|pci|objects|holders|unload]"
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
done

require_root "$0"
bf_ensure_logdir

run_script() {
	local label="$1" script="$2"
	[[ -x "$script" ]] || chmod +x "$script"
	bf_log "=== validate ${label} ==="
	"$script"
}

bf_log "validation log dir: ${BF_LOG_DIR}"
bf_log "goal: confirm actions occur — not recovery PASS"

	case "$PHASE" in
all)
	run_script "V001-modules" "${SCRIPT_DIR}/V001-modules.sh"
	run_script "V002-pci-driver" "${SCRIPT_DIR}/V002-pci-driver.sh"
	run_script "V003-kernel-objects" "${SCRIPT_DIR}/V003-kernel-objects.sh"
	run_script "V005-module-holders" "${SCRIPT_DIR}/V005-module-holders.sh"
	;;
modules) run_script "V001-modules" "${SCRIPT_DIR}/V001-modules.sh" ;;
pci) run_script "V002-pci-driver" "${SCRIPT_DIR}/V002-pci-driver.sh" ;;
objects) run_script "V003-kernel-objects" "${SCRIPT_DIR}/V003-kernel-objects.sh" ;;
holders) run_script "V005-module-holders" "${SCRIPT_DIR}/V005-module-holders.sh" ;;
unload)
	run_script "V003-kernel-objects" "${SCRIPT_DIR}/V003-kernel-objects.sh"
	run_script "V004-unload-delta" "${SCRIPT_DIR}/V004-unload-delta.sh"
	;;
*)
	echo "unknown phase: $PHASE" >&2
	exit 1
	;;
esac

bf_log "validation complete — review logs in ${BF_LOG_DIR}"
