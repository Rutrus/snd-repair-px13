#!/usr/bin/env bash
# V002 — PCI driver path, bind state, FLR/reset/remove sysfs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"

sys="$(pci_sysfs)"
bdf="${PCI_DEV#0000:}"

bf_log "V002: PCI driver validation"
bf_log "lspci -k -s ${bdf}:"
lspci -k -s "$bdf" 2>/dev/null | sed 's/^/[bruteforce]   /'

bf_log "driver readlink: $(readlink -f "${sys}/driver" 2>/dev/null || echo '(none)')"
bf_log "pci_driver_status: $(pci_driver_status 2>&1 || echo FAIL)"

if drv="$(pci_driver_dir 2>/dev/null)"; then
	bf_log "pci_driver_dir OK: $drv"
	bf_log "device bound: $([[ -e "${drv}/${PCI_DEV}" ]] && echo yes || echo no)"
else
	bf_log "pci_driver_dir: MISSING (expected after anchor unload)"
fi

for f in reset remove; do
	p="${sys}/${f}"
	if [[ -w "$p" ]]; then
		bf_log "sysfs ${f}: writable"
	else
		bf_log "sysfs ${f}: not writable or missing"
	fi
done

bf_log "power/control=$(cat "${sys}/power/control" 2>/dev/null || echo ?)"
bf_log "power/runtime_status=$(cat "${sys}/power/runtime_status" 2>/dev/null || echo ?)"
if [[ -w "${sys}/power/state" ]]; then
	bf_log "power/state: writable (unusual on PCI)"
else
	bf_log "power/state: not writable (normal — use runtime PM)"
fi

bf_log "V002 done"
