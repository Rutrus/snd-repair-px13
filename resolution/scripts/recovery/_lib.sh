#!/usr/bin/env bash
# Shared helpers for resolution recovery scripts (binary, one action each).
set -euo pipefail

PCI_DEV="${PX13_PCI_DEV:-0000:c4:00.5}"
PCI_DRV="/sys/bus/pci/drivers/snd_pci_ps"
# PX13 SoundWire manager instance 1 (research: ACP_SDW1)
PX13_MANAGER_PLAT="${PX13_MANAGER_PLAT:-amd_sdw_manager.1}"
PX13_MANAGER_PCI="0000:00:08.1/0000:c4:00.5/${PX13_MANAGER_PLAT}"
PX13_RT721_SDW="${PX13_RT721_SDW:-sdw:0:1:025d:0721:01}"
CARD_MATCH="amd-soundwire"
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# sudo sets HOME=/root — resolve repo from script location, not $HOME
REPO="${SND_REPAIR_REPO:-$(cd "${_LIB_DIR}/../../.." && pwd)}"

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

# PX13 PCI reset — from px13-audio-fix (longer bind wait, FW settle).
pci_reset_acp() {
	local unbind_ok=1

	[[ -d "$PCI_DRV" ]] || {
		log "pci_reset: $PCI_DRV missing"
		return 1
	}

	stop_pipewire_all
	sleep 1

	if [[ ! -e "$PCI_DRV/$PCI_DEV" ]]; then
		log "pci_reset: bind only $PCI_DEV"
		pci_write "$PCI_DEV" "$PCI_DRV/bind" || true
	else
		log "pci_reset: unbind $PCI_DEV"
		if ! pci_write "$PCI_DEV" "$PCI_DRV/unbind"; then
			log "pci_reset: unbind failed/timed out"
			return 1
		fi
		sleep 2
		log "pci_reset: bind $PCI_DEV"
		pci_write "$PCI_DEV" "$PCI_DRV/bind" || true
	fi

	local _
	for _ in $(seq 1 80); do
		[[ -e "$PCI_DRV/$PCI_DEV" ]] && grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && return 0
		sleep 0.25
	done
	log "pci_reset: card did not reappear"
	return 1
}

wait_fw_settle() {
	local sec="${PX13_FW_SETTLE_SEC:-12}"
	log "FW settle ${sec}s before playback witness"
	sleep "$sec"
}

# Kernel witness for S2 (more reliable than playback alone).
witness_journal_since() {
	local ts
	ts="$(journalctl -k -b 0 --no-pager -g 'PM: suspend exit' -o short-iso 2>/dev/null | tail -1 || true)"
	if [[ -n "$ts" ]]; then
		# journalctl --since accepts ISO timestamps
		echo "$ts"
	else
		echo "${1:-5 min ago}"
	fi
}

journal_rt721_timeout() {
	local since="${1:-$(witness_journal_since "3 min ago")}"
	journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -qE 'wait_init_timeout|failed to resume: error -110|resume_exit.*ret=-110|error -110|ret=-110'
}

journal_s2_witness() {
	journal_rt721_timeout
}

journal_suspend_observed() {
	local since="${1:-5 min ago}"
	journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -qE 'PM: suspend (entry|exit)'
}

journal_handler_since_pm_zero() {
	local since="${1:-$(witness_journal_since "3 min ago")}"
	journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -E 'PHASE8 ctx=acp fn=irq_stats' \
		| grep -E 'resume=1.*since_pm=0|since_pm=0.*resume=1' \
		| grep -q .
}

journal_stat1_pending() {
	local since="${1:-$(witness_journal_since "3 min ago")}"
	journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -E 'fn=intr_decode when=post_delay' \
		| grep -qE 'STAT1=0x4|STAT&mask=0x4'
}

# PX13: RT721 wait_init_timeout ~5s after resume; allow kernel log + ALSA to settle.
wait_post_resume_settle() {
	local sec="${PX13_S2_RESUME_WAIT_SEC:-8}"
	local poll max extra

	log "post-resume settle ${sec}s (RT721 timeout ~5s)"
	sleep "$sec"

	# Optional: short poll for -110 if not yet in journal
	if [[ "${PX13_S2_POLL_KERNEL:-1}" == "1" ]] && ! journal_rt721_timeout "$(witness_journal_since "3 min ago")"; then
		max="${PX13_S2_POLL_MAX_SEC:-6}"
		for poll in $(seq 1 "$max"); do
			journal_rt721_timeout "$(witness_journal_since "3 min ago")" && break
			sleep 1
		done
	fi
}

# RT721 Attached in sysfs (post reprobe).
rt721_sysfs_attached() {
	local d name
	for d in /sys/bus/soundwire/devices/*; do
		[[ -r "$d/status" ]] || continue
		name="$(basename "$d")"
		[[ "$name" == *025d:0721* || "$name" == *rt721* ]] || continue
		grep -qi attached "$d/status" 2>/dev/null && return 0
	done
	return 1
}

journal_rt721_attached() {
	local since="${1:-2 min ago}"
	journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -qiE 'rt721.*(ATTACHED|attach|initialization_complete|probe)' && return 0
	rt721_sysfs_attached
}

journal_manager_probe() {
	local since="${1:-2 min ago}"
	journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null \
		| grep -qE 'amd_sdw_manager|SoundWire.*manager|manager.*probe|amd manager'
}

manager_plat_bound() {
	local plat drv_dir
	plat="$(discover_manager_plat 2>/dev/null)" || return 1
	drv_dir="$(manager_platform_driver_dir)"
	[[ -e "${drv_dir}/${plat}" ]]
}

witness_quality_numeric() {
	case "${1:-W0}" in
	W4) echo 4 ;;
	W3) echo 3 ;;
	W2) echo 2 ;;
	W1) echo 1 ;;
	*)  echo 0 ;;
	esac
}

# Assess post-suspend witness. Sets RESOLUTION_WITNESS_* exports.
assess_witness_quality() {
	local window="${1:-$(witness_journal_since "5 min ago")}"
	local w=0 reason="" handler=0 stat1=0

	if journal_suspend_observed "$window"; then
		w=1
	elif [[ "${RESOLUTION_ASSUME_SUSPEND:-0}" == "1" ]]; then
		w=1
		reason="orchestrated suspend (kernel latch may be delayed)"
	else
		reason="no suspend observed in kernel journal"
	fi

	if journal_rt721_timeout "$window"; then
		w=2
		reason="RT721 timeout (-110) in kernel log"
	fi

	# Symptom S2: suspend → no audio (what resolution fixes). Card up, ALSA playback down.
	if [[ "$w" -eq 1 && "${RESOLUTION_ASSUME_SUSPEND:-0}" == "1" ]] && post_resume_audio_broken; then
		w=2
		reason="post-resume audio broken (S2 symptom — card present, ALSA playback fail)"
	fi

	if [[ "$w" -ge 2 ]]; then
		journal_handler_since_pm_zero "$window" && handler=1
		journal_stat1_pending "$window" && stat1=1
		if [[ "$handler" -eq 1 && "$stat1" -eq 1 ]]; then
			w=3
			reason="research S2: -110 + handler_since_pm=0 + STAT1=0x4"
		elif journal_rt721_timeout "$window"; then
			local miss=()
			[[ "$handler" -eq 0 ]] && miss+=("handler_since_pm")
			[[ "$stat1" -eq 0 ]] && miss+=("STAT1=0x4")
			reason="RT721 -110 without full research signature (missing: ${miss[*]:-printk?})"
		fi
	fi

	if [[ "$w" -ge 3 ]] && { ! witness_playback || userspace_audio_broken; }; then
		w=4
		reason="${reason}; alsa/userspace broken ($(userspace_sink_state))"
	fi

	if [[ "$w" -eq 1 ]]; then
		local uspace pb=fail dummy_default=0
		uspace="$(userspace_sink_state)"
		userspace_default_sink_is_dummy && dummy_default=1
		witness_playback_alsa && pb=ok
		if [[ "$pb" == ok && "$uspace" != dummy && "$uspace" != none && "$dummy_default" -eq 0 ]]; then
			reason="suspend ok; real audio still works — bug not reproduced this cycle"
		else
			w=2
			reason="post-resume broken (alsa=${pb}, userspace=${uspace}, dummy_default=${dummy_default})"
		fi
	fi

	[[ "$w" -eq 0 && -z "$reason" ]] && reason="no suspend observed"

	export RESOLUTION_WITNESS_QUALITY="W${w}"
	export RESOLUTION_WITNESS_REASON="$reason"
	export RESOLUTION_USERSPACE_STATE="$(userspace_sink_state)"

	local min="${RESOLUTION_MIN_WITNESS:-W2}"
	local wn mn
	wn="$(witness_quality_numeric "$RESOLUTION_WITNESS_QUALITY")"
	mn="$(witness_quality_numeric "$min")"
	if [[ "$wn" -ge "$mn" ]]; then
		export RESOLUTION_WITNESS_VALID=1
	else
		export RESOLUTION_WITNESS_VALID=0
	fi
}

witness_quality_label() {
	case "${RESOLUTION_WITNESS_QUALITY:-W0}" in
	W4) echo "W4 full S2 (research + broken audio)" ;;
	W3) echo "W3 research S2 signature" ;;
	W2) echo "W2 S2 certified (kernel -110 and/or post-resume audio broken)" ;;
	W1) echo "W1 suspend only — audio still OK" ;;
	*)  echo "W0 no suspend" ;;
	esac
}

# Next suspend attempt only when bug was NOT reproduced (audio still OK at W1).
prepare_s0_for_retry() {
	local since

	since="$(witness_journal_since "3 min ago")"
	wait_post_resume_settle
	assess_witness_quality "$since"
	if [[ "${RESOLUTION_WITNESS_VALID:-0}" == "1" ]]; then
		log "witness VALID — S2 reproduced (post-resume audio broken is expected)"
		return 2
	fi

	if ! alsa_card_present; then
		log "card missing — reboot required"
		[[ "${PX13_S2_AUTO_REBOOT:-0}" == "1" ]] && systemctl reboot
		return 1
	fi

	if confirm_s0_health; then
		log "audio still OK — safe to suspend again"
		return 0
	fi

	# Playback down but not VALID — wait once more for kernel latch
	log "playback down but witness below min — extra settle"
	sleep 5
	assess_witness_quality "$since"
	[[ "${RESOLUTION_WITNESS_VALID:-0}" == "1" ]] && return 2

	log "ambiguous — reboot recommended"
	[[ "${PX13_S2_AUTO_REBOOT:-0}" == "1" ]] && systemctl reboot
	return 1
}

confirm_s2_state() {
	assess_witness_quality
	if [[ "${RESOLUTION_WITNESS_VALID:-0}" == "1" ]]; then
		log "S2: VALID ${RESOLUTION_WITNESS_QUALITY} — $(witness_quality_label)"
		return 0
	fi
	log "S2: INVALID ${RESOLUTION_WITNESS_QUALITY} — ${RESOLUTION_WITNESS_REASON}"
	return 1
}

# Try to drop ALSA users to allow runtime_suspend.
drop_alsa_users() {
	fuser -s -k /dev/snd/pcm* 2>/dev/null || true
	fuser -s -k /dev/snd/controlC* 2>/dev/null || true
	sleep 1
}

discover_sdw_devices() {
	ls -1 /sys/bus/soundwire/devices/ 2>/dev/null || true
}

discover_manager_plat() {
	# Platform device (PX13 instance 1)
	local dev="/sys/devices/pci0000:00/${PX13_MANAGER_PCI}"
	[[ -d "$dev" ]] && { echo "$PX13_MANAGER_PLAT"; return 0; }
	# fallback: any amd_sdw_manager.N under ACP PCI
	local d
	for d in /sys/bus/pci/devices/${PCI_DEV}/amd_sdw_manager.*; do
		[[ -d "$d" ]] || continue
		basename "$d"
		return 0
	done
	return 1
}

discover_manager_dev() {
	# sysfs name under soundwire bus (child of platform manager)
	local plat
	plat="$(discover_manager_plat)" || return 1
	local sw="/sys/bus/soundwire/devices"
	for name in "sdw-master-0-1" "sdw-master-0-0"; do
		[[ -d "${sw}/${name}" ]] && { echo "$name"; return 0; }
	done
	echo "$plat"
	return 0
}

manager_platform_driver_dir() {
	echo "/sys/bus/platform/drivers/amd_sdw_manager"
}

discover_rt721_dev() {
	[[ -d "/sys/bus/soundwire/devices/${PX13_RT721_SDW}" ]] && {
		echo "$PX13_RT721_SDW"
		return 0
	}
	local d name
	for d in /sys/bus/soundwire/devices/*; do
		[[ -d "$d" ]] || continue
		name="$(basename "$d")"
		[[ "$name" == *025d:0721* || "$name" == *rt721* ]] && {
			echo "$name"
			return 0
		}
	done
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

alsa_card_number() {
	awk '/amd-soundwire|ProArtPX13/ {print $1; exit}' /proc/asound/cards 2>/dev/null
}

# Direct ALSA — bypasses PipeWire (required when invoked via sudo).
alsa_speaker_dev() {
	if [[ -n "${PX13_ALSA_DEV:-}" ]]; then
		echo "$PX13_ALSA_DEV"
		return 0
	fi
	local card
	card="$(alsa_card_number)"
	[[ -n "$card" ]] && { echo "plughw:${card},2"; return 0; }
	return 1
}

alsa_card_present() {
	grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null
}

# Logged-in PipeWire/Pulse sink state (post-suspend may be dummy-only or empty).
userspace_sink_state() {
	local uid user_name runtime_dir sinks
	if ! command -v pactl >/dev/null 2>&1; then
		echo unknown
		return 0
	fi
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		runtime_dir="/run/user/$uid"
		[[ -d "$runtime_dir" ]] || continue
		sinks="$(sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			pactl list sinks short 2>/dev/null || true)"
		[[ -z "$sinks" ]] && { echo none; return 0; }
		if echo "$sinks" | grep -qiE 'speaker|proart|alsa|amdsoundwire|PX13'; then
			echo ok
			return 0
		fi
		if echo "$sinks" | grep -qi dummy; then
			echo dummy
			return 0
		fi
		echo none
		return 0
	done
	echo unknown
}

userspace_audio_broken() {
	local st
	st="$(userspace_sink_state)"
	[[ "$st" == dummy || "$st" == none ]]
}

# Default Pulse sink is Dummy Output (speaker-test "passes" with no audible sound).
userspace_default_sink_is_dummy() {
	local uid user_name runtime_dir default
	if ! command -v pactl >/dev/null 2>&1; then
		return 1
	fi
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		runtime_dir="/run/user/$uid"
		[[ -d "$runtime_dir" ]] || continue
		default="$(sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			pactl get-default-sink 2>/dev/null || true)"
		[[ -n "$default" ]] && echo "$default" | grep -qi dummy && return 0
	done
	return 1
}

# Direct ALSA only — never PipeWire/dummy (authoritative for S0/S2).
witness_playback_alsa() {
	local dev card

	if ! command -v speaker-test >/dev/null 2>&1; then
		return 1
	fi
	if ! dev="$(alsa_speaker_dev)"; then
		return 1
	fi
	timeout 6 speaker-test -D "$dev" -c2 -t wav -l 1 -r 48000 >/dev/null 2>&1 && return 0
	card="${dev#plughw:}"
	card="${card%%,*}"
	timeout 6 speaker-test -D "plughw:${card},0" -c2 -t wav -l 1 -r 48000 >/dev/null 2>&1
}

# After suspend: dummy simulates playback but hardware is silent — treat as S2.
post_resume_audio_broken() {
	alsa_card_present || return 1
	userspace_audio_broken && return 0
	userspace_default_sink_is_dummy && return 0
	witness_playback_alsa && return 1
	return 0
}

# Playback witness: ALSA plughw when card present; never count Dummy Output as success.
witness_playback() {
	local uid user_name runtime_dir

	if alsa_card_present; then
		witness_playback_alsa && return 0
		# Card up but ALSA failed — do not fall through to dummy PipeWire
		userspace_default_sink_is_dummy && return 1
		userspace_audio_broken && return 1
		return 1
	fi

	if ! command -v speaker-test >/dev/null 2>&1; then
		return 1
	fi

	# No ALSA card: only accept non-dummy user session
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		runtime_dir="/run/user/$uid"
		[[ -d "$runtime_dir" ]] || continue
		default="$(sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			pactl get-default-sink 2>/dev/null || true)"
		echo "$default" | grep -qi dummy && continue
		if sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			timeout 6 speaker-test -c2 -t wav -l 1 >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

# S0 health: kernel card required; playback via ALSA (not PipeWire default).
confirm_s0_health() {
	if ! alsa_card_present; then
		log "S0 FAIL: no $CARD_MATCH in /proc/asound/cards"
		return 1
	fi
	if witness_playback_alsa; then
		log "S0 OK: amd-soundwire + ALSA playback (${PX13_ALSA_DEV:-$(alsa_speaker_dev)})"
		return 0
	fi
	if [[ "${RESOLUTION_S0_ALSA_ONLY:-0}" == "1" ]]; then
		log "S0 OK (alsa-only): card present, playback skipped"
		return 0
	fi
	log "S0 FAIL: card present but playback failed (sink=$(userspace_sink_state); post-suspend dummy/none is S2 symptom)"
	return 1
}

witness_audio() {
	[[ "${RESOLUTION_ORCHESTRATED:-0}" == "1" ]] && return 0
	log "witness: playback"
	witness_playback
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
