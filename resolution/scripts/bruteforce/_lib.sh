#!/usr/bin/env bash
# Bruteforce recovery — shared helpers (reuses resolution recovery lib).
set -euo pipefail

_BF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../recovery/_lib.sh
source "${_BF_DIR}/../recovery/_lib.sh"

BF_LOG_DIR="${BF_LOG_DIR:-/var/log/snd-repair-bruteforce}"
BF_SETTLE_SEC="${BF_SETTLE_SEC:-3}"
BF_FW_SETTLE_SEC="${BF_FW_SETTLE_SEC:-12}"
BF_ANCHOR_MOD="${BF_ANCHOR_MOD:-snd_pci_ps}"

# PX13 stack modules (informational — unload uses modprobe -r -va anchor).
BF_MODS_PX13=(
	snd_soc_amd_acp_mach
	snd_soc_rt721_sdca
	snd_soc_sdw_utils
	snd_acp_sdw_legacy_mach
	snd_acp_sdw_mach
	snd_ps_sdw_dma
	snd_ps_pdm_dma
	snd_amd_sdw_acpi
	snd_pci_ps
	soundwire_amd
	soundwire_bus
)

bf_log() { echo "[bruteforce] $*"; }

bf_ensure_logdir() {
	mkdir -p "$BF_LOG_DIR" 2>/dev/null || BF_LOG_DIR="${TMPDIR:-/tmp}/snd-repair-bruteforce"
	mkdir -p "$BF_LOG_DIR"
}

bf_timestamp() { date -Iseconds; }

# Entry gate: S2 = card up + ALSA hw broken (plughw PASS alone is NOT healthy).
bf_certify_s2_entry() {
	if ! alsa_card_present; then
		bf_log "S2 entry FAIL: no amd-soundwire card"
		return 1
	fi
	if witness_playback_alsa_hw_primary && userspace_default_sink_is_real; then
		bf_log "S2 entry FAIL: ALSA hw + real default sink — fully working"
		return 1
	fi
	if witness_playback_alsa_hw_primary; then
		bf_log "S2 entry FAIL: primary PCM OK (hw:1,2) — not broken"
		return 1
	fi
	bf_log "S2 entry OK: card present, primary PCM broken (plughw=$(witness_playback_alsa_plughw && echo pass || echo fail))"
	return 0
}

# Per-strategy: skip if hw playback already restored.
bf_require_s2_before_strategy() {
	if [[ "${BF_SKIP_S2_GATE:-0}" == "1" ]]; then
		return 0
	fi
	if ! alsa_card_present; then
		bf_log "pre-strategy SKIP: no ALSA card"
		return 1
	fi
	if witness_playback_alsa_hw_primary && userspace_default_sink_is_real; then
		bf_log "pre-strategy SKIP: primary PCM + real sink (recovered)"
		return 1
	fi
	if witness_playback_alsa_hw_primary; then
		bf_log "pre-strategy SKIP: primary PCM OK (hw:1,2)"
		return 1
	fi
	bf_log "pre-strategy: S2 symptom (card up, primary PCM down)"
	return 0
}

bf_test_alsa() {
	witness_playback_alsa_hw
}

# Strict recovery witness — four automated layers; speaker-test/plughw alone is insufficient.
# L5 (audible sound) remains manual — scripts never emit PASS without L1–L4.
bf_witness_recovery_pass() {
	local sid="${1:-?}"
	local gate=0 us_sink us_default

	wait_post_resume_settle

	bf_log "witness ${sid}: L1 kernel (card + aplay -l)"
	if alsa_card_present && witness_aplay_list_ok; then
		bf_log "  L1 kernel: PASS"
	else
		bf_log "  L1 kernel: FAIL"
		gate=1
	fi

	bf_log "witness ${sid}: L2 ALSA hw ($(alsa_hw_dev 2>/dev/null || echo '?'))"
	if witness_playback_alsa_hw_primary; then
		bf_log "  L2 ALSA hw primary: PASS"
	else
		bf_log "  L2 ALSA hw primary: FAIL (${WITNESS_PCM_LAST_CLASS:-?} rc=${WITNESS_PCM_LAST_RC:-?})"
		[[ -n "${WITNESS_PCM_LAST_ERR:-}" ]] && bf_log "  L2 stderr: ${WITNESS_PCM_LAST_ERR}"
		gate=1
	fi
	if witness_playback_alsa_hw; then
		bf_log "  L2 ALSA hw any: PASS (fallback path)"
	else
		bf_log "  L2 ALSA hw any: FAIL (${WITNESS_PCM_LAST_CLASS:-?})"
	fi
	if witness_playback_alsa_plughw; then
		bf_log "  L2 ALSA plughw: PASS (informational — not sufficient for PASS)"
	else
		bf_log "  L2 ALSA plughw: FAIL (informational)"
	fi
	if witness_aplay_wav_hw; then
		bf_log "  L2 ALSA aplay wav: PASS"
	else
		bf_log "  L2 ALSA aplay wav: FAIL or sample missing"
	fi

	bf_log "witness ${sid}: L3 PipeWire real sink"
	us_sink="$(userspace_sink_presence_quality)"
	if [[ "$us_sink" == real ]]; then
		bf_log "  L3 userspace sink: PASS"
	else
		bf_log "  L3 userspace sink: FAIL (${us_sink})"
		gate=1
	fi
	if [[ -x "${USERSPACE_WPCTL:-/usr/bin/wpctl}" ]]; then
		bf_log "  L3 wpctl: $(userspace_wpctl_summary)"
	fi

	bf_log "witness ${sid}: L4 default sink not dummy"
	us_default="$(userspace_default_sink_quality)"
	if [[ "$us_default" == real ]]; then
		bf_log "  L4 default sink: PASS"
	else
		bf_log "  L4 default sink: FAIL (${us_default})"
		gate=1
	fi

	bf_log "witness ${sid}: RT721 sysfs attached"
	if rt721_sysfs_attached; then
		bf_log "  gate RT721: PASS"
	else
		bf_log "  gate RT721: FAIL"
		gate=1
	fi

	bf_log "witness ${sid}: kernel -110 cleared"
	if journal_rt721_timeout "$(witness_journal_since "3 min ago")"; then
		bf_log "  gate -110: FAIL (timeout still in journal)"
		gate=1
	else
		bf_log "  gate -110: PASS"
	fi

	[[ "$gate" -eq 0 ]]
}

bf_report_partial() {
	local sid="$1" reason="${2:-L1+L2 OK, userspace/PipeWire broken}"
	bf_log "PARTIAL strategy=${sid} time=$(bf_timestamp) — ${reason}"
	echo "RESULT=PARTIAL STRATEGY=${sid} TIME=$(bf_timestamp) REASON=${reason}"
}

bf_strategy_finish() {
	local sid="$1"
	if bf_witness_recovery_pass "$sid"; then
		bf_report_pass "$sid"
		return 0
	fi
	# ALSA/kernel recovered but PipeWire still dummy → PARTIAL (not PASS).
	if alsa_card_present && witness_aplay_list_ok && witness_playback_alsa_hw_primary; then
		bf_report_partial "$sid" "kernel+ALSA hw OK; PipeWire/userspace witness failed"
		return 1
	fi
	if witness_playback_alsa_plughw; then
		bf_log "FALSE_PASS ${sid}: plughw opens but hw/userspace failed"
		echo "RESULT=FALSE_PASS STRATEGY=${sid} TIME=$(bf_timestamp)"
		return 1
	fi
	bf_report_fail "$sid"
	return 1
}

bf_report_pass() {
	local sid="$1"
	bf_log "PASS strategy=${sid} time=$(bf_timestamp) (strict witness)"
	echo "RESULT=PASS STRATEGY=${sid} TIME=$(bf_timestamp)"
}

bf_report_fail() {
	local sid="$1"
	bf_log "FAIL strategy=${sid} time=$(bf_timestamp)"
	echo "RESULT=FAIL STRATEGY=${sid} TIME=$(bf_timestamp)"
}

bf_modprobe_remove_plan() {
	# -n = dry-run only (audit/validate must never unload)
	modprobe -r -n -va "$1" 2>&1
}

bf_modprobe_load_plan() {
	modprobe -n -va "$1" 2>&1
}

bf_module_kind() {
	local m="$1"
	if modinfo "$m" &>/dev/null; then
		echo "module"
	elif [[ -d "/sys/module/$m" ]]; then
		echo "builtin"
	else
		echo "missing"
	fi
}

bf_module_loaded() {
	local m="$1"
	lsmod | awk '{print $1}' | grep -qx "$m"
}

bf_module_users() {
	local m="$1"
	lsmod | awk -v m="$m" '$1 == m { if ($4 != "") print $4; else print "(none)" }'
}

bf_log_loaded_audio_modules() {
	bf_log "lsmod (snd|soundwire|regmap_sdw):"
	lsmod | grep -E 'snd|soundwire|regmap_sdw' || bf_log "(none)"
}

bf_rmmod_verbose() {
	local m="$1" kind users out rc
	kind="$(bf_module_kind "$m")"
	case "$kind" in
	missing)
		bf_log "rmmod $m: skip (no modinfo — not a loadable module; may be autoload alias)"
		return 0
		;;
	builtin)
		bf_log "rmmod $m: skip (built-in kernel object at /sys/module/$m)"
		return 0
		;;
	esac
	if ! bf_module_loaded "$m"; then
		bf_log "rmmod $m: skip (not loaded)"
		return 0
	fi
	users="$(bf_module_users "$m")"
	bf_log "rmmod $m (users=${users})"
	set +e
	out="$(modprobe -r -va "$m" 2>&1)"
	rc=$?
	set -e
	if [[ $rc -eq 0 ]]; then
		[[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/[bruteforce]   /'
		return 0
	fi
	bf_log "rmmod $m: FAILED rc=$rc"
	printf '%s\n' "$out" | sed 's/^/[bruteforce]   /'
	if echo "$out" | grep -qiE 'in use|used by|dependency'; then
		bf_log "rmmod $m: reason=dependencies still active"
	elif echo "$out" | grep -qi 'not found'; then
		bf_log "rmmod $m: reason=module not found in kernel"
	elif echo "$out" | grep -qi 'operation not permitted'; then
		bf_log "rmmod $m: reason=permission (run as root? device open?)"
	fi
	return "$rc"
}

bf_modprobe_verbose() {
	local m="$1" kind out rc
	kind="$(bf_module_kind "$m")"
	case "$kind" in
	missing)
		bf_log "modprobe $m: skip (no modinfo — not a separate module; likely built-in or pulled by anchor)"
		return 0
		;;
	builtin)
		bf_log "modprobe $m: skip (built-in)"
		return 0
		;;
	esac
	if bf_module_loaded "$m"; then
		bf_log "modprobe $m: skip (already loaded)"
		return 0
	fi
	bf_log "modprobe $m"
	set +e
	out="$(modprobe -va "$m" 2>&1)"
	rc=$?
	set -e
	if [[ $rc -eq 0 ]]; then
		[[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/[bruteforce]   /'
		return 0
	fi
	bf_log "modprobe $m: FAILED rc=$rc"
	printf '%s\n' "$out" | sed 's/^/[bruteforce]   /'
	return "$rc"
}

# Unload PX13 ACP stack via anchor (correct dependency order).
bf_unload_audio_modules() {
	local m leftover
	stop_pipewire_all
	drop_alsa_users
	sleep 1
	bf_log "unload anchor: modprobe -r -va ${BF_ANCHOR_MOD}"
	set +e
	bf_rmmod_verbose "$BF_ANCHOR_MOD" || true
	set -e
	sleep 1
	for m in snd_acp_sdw_legacy_mach snd_acp_sdw_mach snd_ps_sdw_dma snd_ps_pdm_dma \
		snd_amd_sdw_acpi snd_soc_rt721_sdca snd_soc_sdw_utils soundwire_amd soundwire_bus; do
		bf_module_loaded "$m" || continue
		bf_rmmod_verbose "$m" || true
	done
	bf_log "post-unload module state:"
	bf_log_loaded_audio_modules
	bf_log "post-unload PCI: $(pci_driver_status 2>&1 || true)"
}

bf_load_audio_modules() {
	bf_log "load anchor: modprobe -va ${BF_ANCHOR_MOD}"
	bf_modprobe_verbose "$BF_ANCHOR_MOD" || true
	sleep 2
	bf_log "post-load module state:"
	bf_log_loaded_audio_modules
	bf_log "post-load PCI: $(pci_driver_status 2>&1 || true)"
}

bf_pci_flr_reset() {
	local rst="${PCI_SYS:-$(pci_sysfs)}/reset"
	[[ -w "$rst" ]] || return 1
	bf_log "PCI FLR reset $PCI_DEV"
	echo 1 >"$rst" 2>/dev/null
}

# Runtime PM only — power/state is not writable on modern PCI.
bf_runtime_pm_cycle() {
	local pwr="${PCI_SYS:-$(pci_sysfs)}/power"
	[[ -d "$pwr" ]] || return 1
	bf_log "runtime PM: control=auto → wait suspended → control=on"
	echo auto >"${pwr}/control" 2>/dev/null || bf_log "  power/control=auto: failed"
	local i
	for i in $(seq 1 45); do
		grep -q suspended "${pwr}/runtime_status" 2>/dev/null && break
		sleep 1
	done
	bf_log "  runtime_status=$(cat "${pwr}/runtime_status" 2>/dev/null || echo ?)"
	echo on >"${pwr}/control" 2>/dev/null || bf_log "  power/control=on: failed"
	sleep 2
}

bf_acpi_d3_d0() {
	local pwr="${PCI_SYS:-$(pci_sysfs)}/power"
	[[ -d "$pwr" ]] || return 1
	bf_log "ACPI/PCI PM via runtime PM (power/state not used — usually EPERM on PCI)"
	bf_runtime_pm_cycle || true
	if [[ -w "${pwr}/state" ]]; then
		bf_log "power/state writable — trying suspend→on"
		echo suspend >"${pwr}/state" 2>/dev/null || bf_log "  power/state=suspend: failed"
		sleep 1
		echo on >"${pwr}/state" 2>/dev/null || bf_log "  power/state=on: failed"
	else
		bf_log "power/state not writable (expected on PCI) — skipped"
	fi
}

bf_kernel_objects_snapshot() {
	local tag="$1"
	local f="${BF_LOG_DIR}/ko-${tag}-$(date +%Y%m%dT%H%M%S).txt"
	local sys bdf
	sys="$(pci_sysfs)"
	bdf="${PCI_DEV#0000:}"
	{
		echo "=== kernel-objects tag=${tag} time=$(bf_timestamp) ==="
		echo "--- lspci -k -s ${bdf} ---"
		lspci -k -s "$bdf" 2>/dev/null || true
		echo "--- pci driver ---"
		readlink -f "${sys}/driver" 2>/dev/null || echo "(none)"
		pci_driver_status 2>/dev/null || true
		echo "--- driver_override ---"
		cat "${sys}/driver_override" 2>/dev/null || echo "(none)"
		echo "--- power ---"
		printf 'control=%s runtime_status=%s runtime_usage=%s\n' \
			"$(cat "${sys}/power/control" 2>/dev/null || echo ?)" \
			"$(cat "${sys}/power/runtime_status" 2>/dev/null || echo ?)" \
			"$(cat "${sys}/power/runtime_usage" 2>/dev/null || echo ?)"
		echo "--- /sys/class/sound ---"
		ls /sys/class/sound/ 2>/dev/null || true
		echo "--- /sys/bus/soundwire/devices ---"
		ls /sys/bus/soundwire/devices/ 2>/dev/null || true
		echo "--- /sys/bus/platform/drivers/amd_sdw_manager ---"
		ls /sys/bus/platform/drivers/amd_sdw_manager/ 2>/dev/null || true
		echo "--- /proc/asound/cards ---"
		cat /proc/asound/cards 2>/dev/null || true
		echo "--- lsmod (snd|soundwire) ---"
		lsmod | grep -E 'snd|soundwire' || true
	} | tee "$f" >/dev/null
	bf_log "kernel-objects snapshot: $f"
	echo "$f"
}

bf_inventory_modules() {
	local m kind
	bf_log "=== module inventory (PX13 audio) ==="
	bf_log_loaded_audio_modules
	for m in "${BF_MODS_PX13[@]}" "$BF_ANCHOR_MOD"; do
		kind="$(bf_module_kind "$m")"
		if [[ "$kind" == "module" ]]; then
			bf_log "modinfo $m: $(modinfo -n "$m" 2>/dev/null || echo ?)"
		else
			bf_log "modinfo $m: ($kind)"
		fi
	done
	bf_log "anchor remove plan (dry-run):"
	set +e
	bf_modprobe_remove_plan "$BF_ANCHOR_MOD" | sed 's/^/[bruteforce]   /' || true
	set -e
	bf_log "anchor load plan (dry-run):"
	set +e
	bf_modprobe_load_plan "$BF_ANCHOR_MOD" | sed 's/^/[bruteforce]   /' || true
	set -e
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
