#!/usr/bin/env bash
# V004 — What disappears after anchor unload? (no reload — diagnostic only).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"

bf_log "V004: kernel-objects delta across anchor unload"
bf_log "WARNING: audio will be down until manual modprobe ${BF_ANCHOR_MOD}"

bf_kernel_objects_snapshot "before_unload"
stop_pipewire_all
drop_alsa_users
bf_unload_audio_modules
sleep +2
bf_kernel_objects_snapshot "after_unload"

bf_log "V004: what remains alive after unload:"
lspci -k -s "${PCI_DEV#0000:}" 2>/dev/null | sed 's/^/[bruteforce]   /' || true
bf_log "driver_override=$(cat "$(pci_sysfs)/driver_override" 2>/dev/null || echo ?)"
bf_log "reload with: modprobe ${BF_ANCHOR_MOD}"
bf_modprobe_verbose "$BF_ANCHOR_MOD" || true
sleep "${BF_FW_SETTLE_SEC}"
bf_kernel_objects_snapshot "after_reload"
start_pipewire_all
bf_log "V004 done"
bf_log "WARNING: audio was reloaded — run s2-reproduce.sh before bruteforce --from-s2"
