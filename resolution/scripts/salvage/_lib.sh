#!/usr/bin/env bash
# Salvage — minimal reconstruction from the bottom up (reuses bruteforce lib).
set -euo pipefail

_SALVAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../bruteforce/_lib.sh
source "${_SALVAGE_DIR}/../bruteforce/_lib.sh"

SALVAGE_LOG_DIR="${SALVAGE_LOG_DIR:-/var/log/snd-repair-salvage}"

salvage_log() { echo "[salvage] $*"; }

salvage_ensure_logdir() {
	mkdir -p "$SALVAGE_LOG_DIR" 2>/dev/null || SALVAGE_LOG_DIR="${TMPDIR:-/tmp}/snd-repair-salvage"
	mkdir -p "$SALVAGE_LOG_DIR"
}

# Log whether a claimed action actually happened (independent of recovery PASS).
salvage_action_ok() {
	local action="$1" detail="${2:-}"
	salvage_log "ACTION_OK ${action}${detail:+ — $detail}"
	echo "RESULT=ACTION_OK ACTION=${action} TIME=$(bf_timestamp)"
}

salvage_action_skip() {
	local action="$1" reason="$2"
	salvage_log "ACTION_SKIP ${action}: ${reason}"
	echo "RESULT=ACTION_SKIP ACTION=${action} REASON=${reason} TIME=$(bf_timestamp)"
}

salvage_module_holders_report() {
	local m holders ref
	salvage_log "=== module holders (snd|soundwire) ==="
	lsmod | grep -E 'snd|soundwire|regmap_sdw' | while read -r line; do
		salvage_log "  $line"
	done
	for m in soundwire_bus soundwire_amd snd_amd_sdw_acpi snd_sof_amd_acp snd_pci_ps \
		snd_soc_rt721_sdca snd_acp_sdw_legacy_mach; do
		if [[ -d "/sys/module/${m}" ]]; then
			ref="$(cat "/sys/module/${m}/refcnt" 2>/dev/null || echo ?)"
			holders="$(lsmod | awk -v m="$m" '$1 == m { print ($4 == "" ? "(none)" : $4) }')"
			salvage_log "  ${m}: refcnt=${ref} used_by=${holders:-?}"
		fi
	done
	salvage_log "=== ALSA device holders ==="
	if fuser -v /dev/snd/* 2>/dev/null | sed 's/^/[salvage]   /'; then
		:
	else
		salvage_log "  (none)"
	fi
}

salvage_sdw_bus_rescan() {
	if [[ -w /sys/bus/soundwire/rescan ]]; then
		salvage_log "echo 1 > /sys/bus/soundwire/rescan"
		echo 1 >/sys/bus/soundwire/rescan
		salvage_action_ok "sdw_bus_rescan" "via rescan"
		return 0
	fi
	if [[ -w /sys/bus/soundwire/drivers_probe ]]; then
		salvage_log "echo soundwire > drivers_probe"
		echo soundwire >/sys/bus/soundwire/drivers_probe
		salvage_action_ok "sdw_bus_rescan" "via drivers_probe"
		return 0
	fi
	salvage_action_skip "sdw_bus_rescan" "no rescan or drivers_probe sysfs"
	return 1
}

salvage_rt721_reprobe() {
	local slave drv drv_dir
	slave="$(discover_rt721_dev)" || {
		salvage_action_skip "rt721_reprobe" "RT721 device not found"
		return 1
	}
	drv_link="/sys/bus/soundwire/devices/${slave}/driver"
	if [[ -e "$drv_link" ]]; then
		drv_dir="$(readlink -f "$drv_link")"
		salvage_log "unbind ${slave} from $(basename "$drv_dir")"
		echo "$slave" >"${drv_dir}/unbind"
		sleep 1
	else
		salvage_log "RT721 ${slave} has no driver — try bus rescan only"
	fi
	if [[ -w /sys/bus/soundwire/drivers_probe ]]; then
		salvage_log "drivers_probe snd_soc_rt721_sdca"
		echo snd_soc_rt721_sdca >/sys/bus/soundwire/drivers_probe 2>/dev/null \
			|| echo "$slave" >/sys/bus/soundwire/drivers_probe 2>/dev/null || true
	fi
	salvage_sdw_bus_rescan || true
	sleep 2
	if rt721_sysfs_attached; then
		salvage_action_ok "rt721_reprobe" "${slave} attached"
		return 0
	fi
	salvage_action_skip "rt721_reprobe" "RT721 not attached after reprobe"
	return 1
}

salvage_manager_rebind() {
	local plat drv_dir
	plat="$(discover_manager_plat)" || {
		salvage_action_skip "manager_rebind" "platform manager not found"
		return 1
	}
	drv_dir="$(manager_platform_driver_dir)"
	if manager_plat_bound; then
		salvage_log "unbind platform ${plat}"
		echo "$plat" >"${drv_dir}/unbind"
		sleep 2
	fi
	salvage_log "bind platform ${plat}"
	echo "$plat" >"${drv_dir}/bind"
	sleep 3
	if manager_plat_bound; then
		salvage_action_ok "manager_rebind" "${plat} bound"
		return 0
	fi
	salvage_action_skip "manager_rebind" "platform did not reappear"
	return 1
}

salvage_drop_pcm_nodes() {
	stop_pipewire_all
	drop_alsa_users
	salvage_log "closed ALSA PCM/control users"
	salvage_action_ok "drop_pcm" "pipewire stopped + fuser"
}

salvage_stop_userspace() {
	stop_pipewire_all
	salvage_action_ok "stop_userspace" "pipewire/wireplumber stopped"
}

# --- Level presence checks (verify destruction) ---

salvage_module_present() {
	bf_module_loaded "$1"
}

salvage_pci_driver_bound() {
	pci_driver_dir &>/dev/null
}

salvage_sdw_devices_count() {
	find /sys/bus/soundwire/devices -mindepth 1 -maxdepth 1 2>/dev/null | wc -l
}

salvage_sof_stack_present() {
	bf_module_loaded snd_sof_amd_acp || bf_module_loaded snd_sof
}

salvage_soundwire_stack_present() {
	bf_module_loaded soundwire_amd || bf_module_loaded soundwire_bus
}

salvage_level_report() {
	local tag="$1"
	salvage_log "LEVEL ${tag}: pci_bound=$(salvage_pci_driver_bound && echo yes || echo no) \
sdw_devs=$(salvage_sdw_devices_count) sof=$(salvage_sof_stack_present && echo yes || echo no) \
sw=$(salvage_soundwire_stack_present && echo yes || echo no) \
snd_pci_ps=$(salvage_module_present snd_pci_ps && echo yes || echo no)"
}

salvage_rmmod_modules() {
	local m out rc
	for m in "$@"; do
		bf_rmmod_verbose "$m" || true
	done
}

# Top-down teardown: userspace → machine → codec → PCI → SOF → SoundWire
# Verify each level; return count of levels fully cleared.
salvage_teardown_topdown() {
	local cleared=0

	salvage_level_report "before"

	salvage_log "TEARDOWN L0 userspace"
	stop_pipewire_all
	drop_alsa_users
	sleep 1
	salvage_level_report "L0"

	salvage_log "TEARDOWN L1 machine+codec"
	salvage_rmmod_modules snd_acp_sdw_legacy_mach snd_acp_sdw_mach snd_soc_sdw_utils \
		snd_soc_rt721_sdca snd_soc_tas2783_sdw snd_ps_sdw_dma snd_ps_pdm_dma
	sleep 1
	salvage_level_report "L1"

	salvage_log "TEARDOWN L2 PCI driver (snd_pci_ps)"
	if salvage_module_present snd_pci_ps; then
		bf_rmmod_verbose snd_pci_ps || true
		sleep 1
	fi
	if salvage_pci_driver_bound; then
		salvage_log "  WARN: PCI still bound after snd_pci_ps removal"
	else
		salvage_log "  OK: PCI driver unbound"
		cleared=$((cleared + 1))
	fi
	salvage_level_report "L2"

	salvage_log "TEARDOWN L3 SOF stack"
	salvage_rmmod_modules snd_sof_amd_acp63 snd_sof_amd_acp70 snd_sof_amd_rembrandt \
		snd_sof_amd_vangogh snd_sof_amd_renoir snd_sof_amd_acp snd_sof_pci snd_sof
	sleep 1
	if salvage_sof_stack_present; then
		salvage_log "  WARN: SOF modules still loaded"
	else
		salvage_log "  OK: SOF stack gone"
		cleared=$((cleared + 1))
	fi
	salvage_level_report "L3"

	salvage_log "TEARDOWN L4 SoundWire"
	salvage_rmmod_modules snd_amd_sdw_acpi soundwire_amd soundwire_bus
	sleep 1
	if salvage_soundwire_stack_present; then
		salvage_log "  WARN: SoundWire modules still loaded (check Used by above)"
	else
		salvage_log "  OK: SoundWire stack gone"
		cleared=$((cleared + 1))
	fi
	salvage_level_report "L4"

	salvage_module_holders_report
	echo "$cleared"
}

salvage_rebuild_bottomup() {
	salvage_log "REBUILD: soundwire → snd_pci_ps anchor"
	modprobe soundwire_bus 2>/dev/null || true
	modprobe soundwire_amd 2>/dev/null || true
	modprobe -va "$BF_ANCHOR_MOD" 2>&1 | sed 's/^/[salvage]   /' || true
	sleep "${BF_FW_SETTLE_SEC}"
	salvage_level_report "after_rebuild"
}

# Unbind every SoundWire device that has a driver.
salvage_sdw_unbind_all() {
	local d name drv_dir unbound=0
	for d in /sys/bus/soundwire/devices/*; do
		[[ -d "$d" ]] || continue
		name="$(basename "$d")"
		[[ -e "${d}/driver" ]] || continue
		drv_dir="$(readlink -f "${d}/driver")"
		salvage_log "sdw unbind ${name} from $(basename "$drv_dir")"
		echo "$name" >"${drv_dir}/unbind" 2>/dev/null && unbound=$((unbound + 1)) || true
	done
	salvage_log "sdw unbind count: ${unbound}"
	[[ "$unbound" -gt 0 ]]
}

# Full stack destroy — SOF must go before SoundWire. Returns 0 if all three gone.
salvage_full_stack_destroy() {
	local ok=1
	salvage_teardown_topdown >/dev/null
	if ! salvage_pci_driver_bound && ! salvage_sof_stack_present && ! salvage_soundwire_stack_present; then
		ok=0
		salvage_log "FULL_DESTROY: pci+sof+soundwire gone"
	else
		salvage_log "FULL_DESTROY: partial — see LEVEL above"
		salvage_module_holders_report
	fi
	return "$ok"
}

salvage_pci_remove_long() {
	local dev settle="${RESCUE_PCI_SETTLE_SEC:-10}"
	dev="$(pci_sysfs)"
	stop_pipewire_all
	drop_alsa_users
	salvage_log "PCI remove ${PCI_DEV} (settle ${settle}s before rescan)"
	echo 1 >"${dev}/remove"
	sleep 2
	echo 1 >/sys/bus/pci/rescan
	salvage_log "waiting ${settle}s post-rescan"
	sleep "$settle"
	udevadm settle 2>/dev/null || true
}

