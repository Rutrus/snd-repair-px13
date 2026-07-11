#!/usr/bin/env bash
# R04 — Layer 2: platform manager unbind + bind (PX13 instance 1).
# Logs M1 unbind / M2 probe / M3 RT721 ATTACHED (informative; PASS = ALSA only).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

require_root "$0"
stop_pipewire_all

ACTION_SINCE="$(date -Iseconds)"

plat="$(discover_manager_plat)" || {
	log "R04-M1 FAIL: platform manager not found"
	exit 1
}

drv_dir="$(manager_platform_driver_dir)"
[[ -d "$drv_dir" ]] || { log "R04: $drv_dir missing"; exit 1; }

log "R04: rebind platform manager ${plat} (L2)"

# --- M1: unbind ---
if manager_plat_bound; then
	log "R04-M1: unbind ${plat}"
	echo "$plat" > "${drv_dir}/unbind"
	sleep 2
else
	log "R04-M1: ${plat} not bound (already unbound?)"
fi

if manager_plat_bound; then
	log "R04-M1 FAIL: platform still present under ${drv_dir}/${plat}"
	export RESOLUTION_R04_M1=fail
	exit 1
fi
log "R04-M1 OK: platform device gone"
export RESOLUTION_R04_M1=ok

# --- M2: bind → probe path ---
log "R04-M2: bind ${plat}"
echo "$plat" > "${drv_dir}/bind"

m2=0
for _ in $(seq 1 60); do
	manager_plat_bound && m2=1 && break
	sleep 0.25
done
if [[ "$m2" -ne 1 ]]; then
	log "R04-M2 FAIL: platform did not reappear after bind"
	export RESOLUTION_R04_M2=fail
	exit 1
fi

if journal_manager_probe "$ACTION_SINCE"; then
	log "R04-M2 OK: manager activity in kernel log since bind"
	export RESOLUTION_R04_M2=probe
elif journal_manager_probe "2 min ago"; then
	log "R04-M2 PARTIAL: platform back, no probe line in journal (check dmesg)"
	export RESOLUTION_R04_M2=bound
else
	log "R04-M2 WARN: platform bound, no manager printk"
	export RESOLUTION_R04_M2=bound
fi

# --- M3: RT721 enumeration ---
sleep 2
for _ in $(seq 1 40); do
	if rt721_sysfs_attached || journal_rt721_attached "$ACTION_SINCE"; then
		log "R04-M3 OK: RT721 ATTACHED (sysfs or journal)"
		export RESOLUTION_R04_M3=attached
		break
	fi
	sleep 0.25
done
if [[ "${RESOLUTION_R04_M3:-}" != "attached" ]]; then
	log "R04-M3 FAIL: no RT721 ATTACHED witness"
	export RESOLUTION_R04_M3=fail
fi

for _ in $(seq 1 40); do
	grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && break
	sleep 0.25
done

start_pipewire_all
if [[ -n "${RESOLUTION_R04_MOMENTS_FILE:-}" ]]; then
	cat >"${RESOLUTION_R04_MOMENTS_FILE}" <<EOF
RESOLUTION_R04_M1=${RESOLUTION_R04_M1:-?}
RESOLUTION_R04_M2=${RESOLUTION_R04_M2:-?}
RESOLUTION_R04_M3=${RESOLUTION_R04_M3:-?}
EOF
fi
log "R04 done — PASS/FAIL decided by ALSA plughw only (run-recovery)"
