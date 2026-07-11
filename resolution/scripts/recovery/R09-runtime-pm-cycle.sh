#!/usr/bin/env bash
# R09 — Layer 4: runtime PM cycle after broken system resume (HIGH PRIORITY).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

dev="$(pci_sysfs)"
ctrl="${dev}/power/control"
status="${dev}/power/runtime_status"

[[ -r "$ctrl" ]] || {
	log "R09: $ctrl missing"
	exit 1
}

log "R09: runtime PM cycle on $PCI_DEV (L4)"
log "  before: control=$(cat "$ctrl") runtime_status=$(cat "$status" 2>/dev/null || echo ?)"

echo auto > "$ctrl" 2>/dev/null || true
[[ -w "${dev}/power/autosuspend_delay_ms" ]] && echo 0 > "${dev}/power/autosuspend_delay_ms" 2>/dev/null || true

# idle long enough for runtime suspend
sleep 3
log "  mid: runtime_status=$(cat "$status" 2>/dev/null || echo ?)"

# force wake
echo on > "$ctrl"
sleep 2
echo auto > "$ctrl" 2>/dev/null || true
sleep 2
log "  after: runtime_status=$(cat "$status" 2>/dev/null || echo ?)"

start_pipewire_all
witness_audio
log "R09 done — if PASS, bug is likely system PM path; see experiments/R004-runtime-pm-repair.md"
