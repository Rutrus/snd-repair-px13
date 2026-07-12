#!/usr/bin/env bash
# Audit recovery framework — read-only checks (never unloads modules).
# Usage: sudo audit-framework.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_root "$0"
salvage_ensure_logdir
REPO="${SND_REPAIR_REPO:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

report() {
	local status="$1" check="$2" detail="$3"
	printf '[audit] %-5s %-28s %s\n' "$status" "$check" "$detail"
}

salvage_log "framework audit — $(bf_timestamp) (read-only)"
salvage_log "log: ${SALVAGE_LOG_DIR}"

# 0. Boot audio present?
if alsa_card_present; then
	report OK "boot_audio" "amd-soundwire in /proc/asound/cards"
else
	report FAIL "boot_audio" "card missing — run restore-boot-audio.sh before S2/salvage"
fi

# 1. Phantom modules (snd_soc_amd_ps etc.)
for m in snd_soc_amd_ps snd_soc_amd_acp_mach; do
	if modinfo "$m" &>/dev/null; then
		report OK "modinfo:${m}" "$(modinfo -n "$m" 2>/dev/null)"
	else
		report WARN "modinfo:${m}" "missing — do not treat modprobe fail as error"
	fi
done

report INFO "anchor" "${BF_ANCHOR_MOD}"

# 2. Who holds soundwire? (live state first)
salvage_module_holders_report

# 3. PCI reprobe preconditions
sys="$(pci_sysfs)"
if drv="$(pci_driver_dir 2>/dev/null)"; then
	report OK "pci_driver" "bound $(basename "$drv")"
	if [[ -w "${drv}/unbind" ]]; then
		report OK "pci_unbind" "writable"
	else
		report FAIL "pci_unbind" "not writable"
	fi
else
	report FAIL "pci_driver" "not bound — pci_reset will skip"
fi
if [[ -w "${sys}/remove" ]]; then
	report OK "pci_remove" "writable (remove+rescan path)"
else
	report FAIL "pci_remove" "not writable"
fi
if [[ -w "${sys}/reset" ]]; then
	report OK "pci_flr" "writable"
else
	report WARN "pci_flr" "not writable on this device"
fi

# 4. power/state vs power/control
if [[ -w "${sys}/power/state" ]]; then
	report WARN "power/state" "writable (unusual)"
else
	report OK "power/state" "not writable — use power/control only"
fi
report INFO "power/control" "$(cat "${sys}/power/control" 2>/dev/null || echo ?)"
report INFO "runtime_status" "$(cat "${sys}/power/runtime_status" 2>/dev/null || echo ?)"

# 5. SoundWire bus controls
for f in /sys/bus/soundwire/rescan /sys/bus/soundwire/drivers_probe; do
	if [[ -w "$f" ]]; then
		report OK "sdw:$(basename "$f")" "writable"
	elif [[ "$(basename "$f")" == "rescan" && -w /sys/bus/soundwire/drivers_probe ]]; then
		report WARN "sdw:rescan" "not writable — use drivers_probe (OK on PX13)"
	else
		report FAIL "sdw:$(basename "$f")" "missing or not writable"
	fi
done

# 6. RT721 + manager paths
if slave="$(discover_rt721_dev 2>/dev/null)"; then
	report OK "rt721_sysfs" "$slave"
	[[ -e "/sys/bus/soundwire/devices/${slave}/driver" ]] \
		&& report OK "rt721_driver" "bound" \
		|| report WARN "rt721_driver" "unbound"
else
	report FAIL "rt721_sysfs" "not found"
fi
if plat="$(discover_manager_plat 2>/dev/null)"; then
	report OK "manager_plat" "$plat"
else
	report FAIL "manager_plat" "not found"
fi

# 7. Dry-run unload plan (does NOT execute)
report INFO "anchor_remove_plan" "(dry-run)"
bf_modprobe_remove_plan "$BF_ANCHOR_MOD" 2>&1 | sed 's/^/[audit]   /' || true

# 8. Strategy execution traps
report INFO "trap:pci_reset" "must run BEFORE anchor unload or driver sysfs vanishes"
report INFO "trap:unload" "snd_sof_amd_acp holds soundwire_amd — partial unload expected"
report INFO "trap:witness" "speaker-test alone = FALSE_PASS; need RT721+-110 gates"
report INFO "trap:audit" "never run modprobe -r without -n in audit/validate"

# 9. Bruteforce strategy order check
if [[ -f "${REPO}/resolution/bruteforce/strategies.yaml" ]]; then
	report OK "bruteforce_index" "present"
else
	report FAIL "bruteforce_index" "missing"
fi

salvage_log "audit complete — see ${REPO}/resolution/salvage/AUDIT.md"
if ! alsa_card_present; then
	salvage_log "RECOVERY: sudo ${SCRIPT_DIR}/restore-boot-audio.sh"
else
	salvage_log "next: s2-reproduce.sh then run-salvage.sh --from-s2"
fi
