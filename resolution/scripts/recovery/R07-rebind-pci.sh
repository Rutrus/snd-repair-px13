#!/usr/bin/env bash
# R07 — Layer 4: PCI driver unbind + bind (ACP) — boot replay step 2.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

[[ -d "$PCI_DRV" ]] || {
	log "R07: driver $PCI_DRV missing"
	exit 1
}

log "R07: PCI unbind+bind $PCI_DEV (L4)"

if [[ -e "$PCI_DRV/$PCI_DEV" ]]; then
	pci_write "$PCI_DEV" "$PCI_DRV/unbind" || {
		log "unbind failed"
		exit 1
	}
	sleep 2
fi

pci_write "$PCI_DEV" "$PCI_DRV/bind" || {
	log "bind failed"
	exit 1
}

for _ in $(seq 1 40); do
	grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && break
	sleep 0.25
done

start_pipewire_all
witness_audio
log "R07 done — record PASS/FAIL in resolution/TRACKER.md"
