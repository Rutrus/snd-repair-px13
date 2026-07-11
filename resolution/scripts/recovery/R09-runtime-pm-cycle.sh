#!/usr/bin/env bash
# R09 — Runtime PM domain: force runtime_suspend → runtime_resume on ACP PCI.
# Domain test invalid unless runtime_status reaches 'suspended'.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all
drop_alsa_users
sleep 2

dev="$(pci_sysfs)"
ctrl="${dev}/power/control"
status="${dev}/power/runtime_status"
enabled="${dev}/power/runtime_enabled"

[[ -r "$ctrl" ]] || { log "R09: $ctrl missing"; exit 1; }

log "R09: runtime PM domain on $PCI_DEV (L4)"
log "  runtime_enabled=$(cat "$enabled" 2>/dev/null || echo ?)"
log "  before: control=$(cat "$ctrl") status=$(cat "$status" 2>/dev/null || echo ?)"

# Aggressive idle: drop all snd nodes again after settle
fuser -s -k /dev/snd/* 2>/dev/null || true
sleep 1

echo auto > "$ctrl" 2>/dev/null || true
[[ -w "${dev}/power/autosuspend_delay_ms" ]] && echo 0 > "${dev}/power/autosuspend_delay_ms" 2>/dev/null || true

local_status="active"
max_wait="${PX13_R09_SUSPEND_WAIT_SEC:-45}"
for i in $(seq 1 "$max_wait"); do
	local_status="$(cat "$status" 2>/dev/null || echo ?)"
	[[ "$local_status" == "suspended" ]] && break
	[[ "$((i % 10))" -eq 0 ]] && log "  waiting runtime_suspend… ${i}s status=$local_status"
	sleep 1
done

if [[ "$local_status" == "suspended" ]]; then
	log "R09-D1 OK: runtime_suspend reached"
	export RESOLUTION_R09_D1=suspended
else
	log "R09-D1 FAIL: runtime_suspend NOT reached (status=$local_status) — domain test incomplete"
	export RESOLUTION_R09_D1=active
fi

echo on > "$ctrl"
sleep 2
echo auto > "$ctrl" 2>/dev/null || true
sleep 2
log "  after: control=$(cat "$ctrl") status=$(cat "$status" 2>/dev/null || echo ?)"
export RESOLUTION_R09_D2="$(cat "$status" 2>/dev/null || echo ?)"

if [[ -n "${RESOLUTION_R09_MOMENTS_FILE:-}" ]]; then
	cat >"${RESOLUTION_R09_MOMENTS_FILE}" <<EOF
RESOLUTION_R09_D1=${RESOLUTION_R09_D1:-?}
RESOLUTION_R09_D2=${RESOLUTION_R09_D2:-?}
EOF
fi

start_pipewire_all
log "R09 done — PASS/FAIL = ALSA plughw only"
