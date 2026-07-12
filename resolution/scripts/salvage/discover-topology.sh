#!/usr/bin/env bash
# Discover live kernel audio topology — no hardcoded PX13 names.
# Usage: sudo discover-topology.sh [--emit path]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_root "$0"
salvage_ensure_logdir

EMIT=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--emit) EMIT="${2:?}"; shift 2 ;;
	-h | --help)
		echo "Usage: sudo $0 [--emit /path/topology.txt]"
		exit 0
		;;
	*) echo "unknown: $1" >&2; exit 1 ;;
	esac
done

OUT="${EMIT:-${SALVAGE_LOG_DIR}/topology-$(date +%Y%m%dT%H%M%S).txt}"

emit() { printf '%s\n' "$*" >>"$OUT"; }

: >"$OUT"
emit "=== SALVAGE TOPOLOGY $(bf_timestamp) ==="
emit "kernel: $(uname -r)"
emit ""

emit "--- PCI ACP / snd_pci_ps (anchor ${PCI_DEV}) ---"
if [[ -d "/sys/bus/pci/devices/${PCI_DEV}" ]]; then
	dev="/sys/bus/pci/devices/${PCI_DEV}"
	bdf="${PCI_DEV#0000:}"
	emit "device ${PCI_DEV}"
	lspci -k -s "$bdf" 2>/dev/null | sed 's/^/  /' >>"$OUT" || true
	emit "  class: $(cat "${dev}/class" 2>/dev/null || echo ?)"
	if [[ -e "${dev}/driver" ]]; then
		emit "  driver_link: $(readlink -f "${dev}/driver" 2>/dev/null || echo ?)"
	else
		emit "  driver_link: (none)"
	fi
	emit "  driver_override: $(cat "${dev}/driver_override" 2>/dev/null || echo ?)"
	emit "  power: control=$(cat "${dev}/power/control" 2>/dev/null) runtime=$(cat "${dev}/power/runtime_status" 2>/dev/null)"
	emit "  pci_remove: $([[ -w "${dev}/remove" ]] && echo writable || echo no)"
	emit "  children:"
	for child in "${dev}"/*; do
		[[ -d "$child" ]] || continue
		base="$(basename "$child")"
		[[ "$base" =~ ^(power|driver|subsystem|modalias|config|resource|aer|msi_irqs|irq|iommu) ]] && continue
		emit "    ${base}"
	done
	emit ""
else
	emit "  ${PCI_DEV}: NOT PRESENT"
	emit ""
fi

emit "--- PCI audio (AMD class 04xx) ---"
_seen=""
while IFS= read -r dev; do
	[[ -n "$dev" ]] || continue
	[[ "$dev" == "/sys/bus/pci/devices/${PCI_DEV}" ]] && continue
	bdf="${dev##*/}"
	emit "device ${bdf}"
	lspci -k -s "${bdf#0000:}" 2>/dev/null | sed 's/^/  /' >>"$OUT" || true
	if [[ -e "${dev}/driver" ]]; then
		emit "  driver_link: $(readlink -f "${dev}/driver" 2>/dev/null || echo ?)"
	else
		emit "  driver_link: (none)"
	fi
	emit "  driver_override: $(cat "${dev}/driver_override" 2>/dev/null || echo ?)"
	emit "  power: control=$(cat "${dev}/power/control" 2>/dev/null) runtime=$(cat "${dev}/power/runtime_status" 2>/dev/null)"
	emit "  pci_remove: $([[ -w "${dev}/remove" ]] && echo writable || echo no)"
	emit ""
done < <(find /sys/bus/pci/devices -maxdepth 1 2>/dev/null | while read -r d; do
	[[ -d "$d" ]] || continue
	grep -qiE '0x1022|0x1002' "${d}/vendor" 2>/dev/null || continue
	class="$(cat "${d}/class" 2>/dev/null || true)"
	[[ "$class" == 0x04* ]] || continue
	echo "$d"
done)

emit "--- Platform devices (amd|sdw|acp|audio) ---"
find /sys/bus/platform/devices -maxdepth 1 -mindepth 1 2>/dev/null | while read -r p; do
	base="$(basename "$p")"
	[[ "$base" =~ amd|sdw|acp|audio|dmic ]] || continue
	drv="(none)"
	[[ -e "${p}/driver" ]] && drv="$(basename "$(readlink -f "${p}/driver")")"
	emit "  ${base} driver=${drv}"
done >>"$OUT"

emit ""
emit "--- SoundWire bus ---"
emit "  rescan: $([[ -w /sys/bus/soundwire/rescan ]] && echo writable || echo no)"
emit "  drivers_probe: $([[ -w /sys/bus/soundwire/drivers_probe ]] && echo writable || echo no)"
emit "  devices:"
for d in /sys/bus/soundwire/devices/*; do
	[[ -d "$d" ]] || continue
	name="$(basename "$d")"
	status="$(cat "${d}/status" 2>/dev/null || echo ?)"
	drv="(none)"
	[[ -e "${d}/driver" ]] && drv="$(basename "$(readlink -f "${d}/driver")")"
	emit "    ${name} status=${status} driver=${drv}"
done

emit ""
emit "--- ALSA ---"
cat /proc/asound/cards 2>/dev/null | sed 's/^/  /' >>"$OUT" || emit "  (no cards)"

emit ""
emit "--- Module graph (snd|soundwire|regmap_sdw) ---"
lsmod | grep -E 'snd|soundwire|regmap_sdw' | sed 's/^/  /' >>"$OUT" || emit "  (none)"

emit ""
emit "--- Key holders ---"
for m in snd_pci_ps snd_sof_amd_acp soundwire_amd soundwire_bus snd_amd_sdw_acpi \
	snd_acp_sdw_legacy_mach snd_soc_rt721_sdca; do
	if [[ -d "/sys/module/${m}" ]]; then
		ref="$(cat "/sys/module/${m}/refcnt" 2>/dev/null || echo ?)"
		used="$(lsmod | awk -v m="$m" '$1==m {print ($4==""?"(none)":$4)}')"
		emit "  ${m}: refcnt=${ref} used_by=${used}"
	else
		emit "  ${m}: (not loaded)"
	fi
done

emit ""
emit "--- modinfo anchors ---"
for m in snd_pci_ps snd_sof_amd_acp soundwire_amd snd_acp_sdw_legacy_mach snd_soc_rt721_sdca \
	snd_soc_amd_ps snd_soc_amd_acp_mach; do
	if modinfo "$m" &>/dev/null; then
		emit "  ${m}: $(modinfo -n "$m" 2>/dev/null)"
	else
		emit "  ${m}: MISSING"
	fi
done

emit ""
emit "=== END TOPOLOGY ==="
salvage_log "topology written: ${OUT}"
cat "$OUT"
