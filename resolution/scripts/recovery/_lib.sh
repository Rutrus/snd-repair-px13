#!/usr/bin/env bash
# Shared helpers for resolution recovery scripts (binary, one action each).
set -euo pipefail

PCI_DEV="${PX13_PCI_DEV:-0000:c4:00.5}"
PCI_DRV="/sys/bus/pci/drivers/snd_pci_ps"
CARD_MATCH="amd-soundwire"
REPO="${SND_REPAIR_REPO:-${HOME}/snd_repair}"

log() { echo "[recovery] $*"; }

require_root() {
	[[ "${EUID:-$(id -u)}" -eq 0 ]] || {
		echo "run as root: sudo $*" >&2
		exit 1
	}
}

pci_sysfs() {
	echo "/sys/bus/pci/devices/${PCI_DEV}"
}

pci_write() {
	timeout 30 sh -c "echo '$1' > '$2'" 2>/dev/null
}

discover_sdw_devices() {
	ls -1 /sys/bus/soundwire/devices/ 2>/dev/null || true
}

discover_manager_dev() {
	# AMD SoundWire manager on PX13 — first non-slave device
	local d
	for d in /sys/bus/soundwire/devices/*; do
		[[ -d "$d" ]] || continue
		[[ -e "$d/status" ]] || continue
		basename "$d"
		return 0
	done
	return 1
}

discover_rt721_dev() {
	local d name
	for d in /sys/bus/soundwire/devices/*; do
		[[ -d "$d" ]] || continue
		name="$(basename "$d")"
		[[ "$name" == *rt721* || "$name" == *721* ]] && {
			echo "$name"
			return 0
		}
	done
	# fallback: slave with Attached in name heuristics
	for d in /sys/bus/soundwire/devices/*; do
		[[ -d "$d/driver" ]] || continue
		if [[ "$(readlink -f "$d/driver" 2>/dev/null)" == *rt721* ]]; then
			basename "$d"
			return 0
		fi
	done
	return 1
}

manager_driver_dir() {
	# soundwire-amd binds managers
	for drv in /sys/bus/soundwire/drivers/*; do
		[[ -d "$drv" ]] || continue
		if [[ "$(basename "$drv")" == *amd* || "$(basename "$drv")" == *soundwire* ]]; then
			echo "$drv"
			return 0
		fi
	done
	return 1
}

witness_audio() {
	[[ "${RESOLUTION_ORCHESTRATED:-0}" == "1" ]] && return 0
	if command -v speaker-test >/dev/null 2>&1; then
		log "witness: speaker-test (5s)"
		timeout 6 speaker-test -c2 -t wav -l 1 || return 1
	else
		log "witness: speaker-test not installed — check audio manually"
	fi
}

stop_pipewire_all() {
	local uid user_name runtime_dir
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		runtime_dir="/run/user/$uid"
		[[ -d "$runtime_dir" ]] || continue
		sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			systemctl --user stop wireplumber pipewire-pulse pipewire 2>/dev/null || true
	done
}

start_pipewire_all() {
	local uid user_name runtime_dir
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		runtime_dir="/run/user/$uid"
		[[ -d "$runtime_dir" ]] || continue
		sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null || true
	done
}
