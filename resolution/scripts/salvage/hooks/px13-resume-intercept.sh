#!/usr/bin/env bash
# systemd-sleep hook — run salvage steps during resume (before RT721 timeout).
# Install: see hooks/README.md
set -euo pipefail

[[ "${PX13_SALVAGE_HOOK:-0}" == "1" ]] || exit 0
[[ "${1:-}" == post ]] || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib.sh
source "${HOOK_DIR}/../_lib.sh"

salvage_ensure_logdir
LOG="${SALVAGE_LOG_DIR}/hook-$(date +%Y%m%dT%H%M%S).log"
exec >>"$LOG" 2>&1

salvage_log "resume intercept post — $(bf_timestamp)"
sleep 1

salvage_sdw_bus_rescan || true
sleep 2
salvage_rt721_reprobe || true

if [[ "${PX13_SALVAGE_HOOK_MANAGER:-0}" == "1" ]]; then
	salvage_manager_rebind || true
fi

# Never PCI remove on resume unless explicitly enabled
if [[ "${PX13_SALVAGE_HOOK_PCI:-0}" == "1" ]]; then
	pci_remove_rescan || true
fi

salvage_log "hook done — check ALSA after login"
