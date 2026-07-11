#!/usr/bin/env bash
# Bruteforce recovery — shared helpers (reuses resolution recovery lib).
set -euo pipefail

_BF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../recovery/_lib.sh
source "${_BF_DIR}/../recovery/_lib.sh"

BF_LOG_DIR="${BF_LOG_DIR:-/var/log/snd-repair-bruteforce}"
BF_SETTLE_SEC="${BF_SETTLE_SEC:-3}"
BF_FW_SETTLE_SEC="${BF_FW_SETTLE_SEC:-12}"
BF_PLUGHw="${PX13_ALSA_DEV:-plughw:1,2}"

# PX13 audio module unload order (dependents first).
BF_MODS_REMOVE=(
	snd_soc_amd_acp_mach
	snd_soc_rt721_sdca
	snd_soc_sdw_utils
	snd_soc_amd_ps
	snd_pci_ps
	soundwire_amd
	soundwire_bus
)

BF_MODS_LOAD=(
	soundwire_bus
	soundwire_amd
	snd_pci_ps
	snd_soc_amd_ps
	snd_soc_sdw_utils
	snd_soc_rt721_sdca
	snd_soc_amd_acp_mach
)

bf_log() { echo "[bruteforce] $*"; }

bf_ensure_logdir() {
	mkdir -p "$BF_LOG_DIR" 2>/dev/null || BF_LOG_DIR="${TMPDIR:-/tmp}/snd-repair-bruteforce"
	mkdir -p "$BF_LOG_DIR"
}

bf_timestamp() { date -Iseconds; }

bf_test_alsa() {
	witness_playback_alsa
}

bf_report_pass() {
	local sid="$1"
	bf_log "PASS strategy=${sid} time=$(bf_timestamp)"
	echo "RESULT=PASS STRATEGY=${sid} TIME=$(bf_timestamp)"
}

bf_report_fail() {
	local sid="$1"
	bf_log "FAIL strategy=${sid} time=$(bf_timestamp)"
	echo "RESULT=FAIL STRATEGY=${sid} TIME=$(bf_timestamp)"
}

bf_unload_audio_modules() {
	local m
	for m in "${BF_MODS_REMOVE[@]}"; do
		if lsmod | awk '{print $1}' | grep -qx "$m"; then
			bf_log "rmmod $m"
			modprobe -r "$m" 2>/dev/null || bf_log "rmmod $m skipped/failed"
		fi
	done
}

bf_load_audio_modules() {
	local m
	for m in "${BF_MODS_LOAD[@]}"; do
		bf_log "modprobe $m"
		modprobe "$m" 2>/dev/null || bf_log "modprobe $m failed"
	done
}

bf_pci_flr_reset() {
	local rst="${PCI_SYS:-$(pci_sysfs)}/reset"
	[[ -w "$rst" ]] || return 1
	bf_log "PCI FLR reset $PCI_DEV"
	echo 1 >"$rst" 2>/dev/null
}

bf_runtime_pm_cycle() {
	local pwr="${PCI_SYS:-$(pci_sysfs)}/power"
	[[ -d "$pwr" ]] || return 1
	bf_log "runtime PM: auto → wait suspended → on"
	echo auto >"${pwr}/control" 2>/dev/null || true
	local i
	for i in $(seq 1 45); do
		grep -q suspended "${pwr}/runtime_status" 2>/dev/null && break
		sleep 1
	done
	echo on >"${pwr}/control" 2>/dev/null || true
	sleep 2
}

bf_acpi_d3_d0() {
	local pwr="${PCI_SYS:-$(pci_sysfs)}/power"
	[[ -d "$pwr" ]] || return 1
	bf_log "ACPI PM: auto → on → suspend → resume"
	echo auto >"${pwr}/control" 2>/dev/null || true
	echo on >"${pwr}/control" 2>/dev/null || true
	echo suspend >"${pwr}/state" 2>/dev/null || true
	sleep 1
	echo on >"${pwr}/state" 2>/dev/null || true
	sleep 2
}

bf_udev_trigger() {
	bf_log "udevadm trigger sound subsystem"
	udevadm trigger --subsystem-match=sound 2>/dev/null || true
	udevadm settle 2>/dev/null || true
}

bf_alsactl_restore() {
	local st="${ALSA_STATE:-/var/lib/alsa/asound.state}"
	[[ -f "$st" ]] || return 0
	bf_log "alsactl restore"
	alsactl restore 2>/dev/null || true
}

bf_restart_pipewire_users() {
	local uid user_name runtime_dir
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		runtime_dir="/run/user/$uid"
		[[ -d "$runtime_dir" ]] || continue
		sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			systemctl --user restart pipewire wireplumber pipewire-pulse 2>/dev/null || true
	done
}
