#!/usr/bin/env bash
# Shared helpers for resolution recovery scripts (binary, one action each).
set -euo pipefail

PCI_DEV="${PX13_PCI_DEV:-0000:c4:00.5}"
PCI_DRV="${PX13_PCI_DRV:-/sys/bus/pci/drivers/snd_pci_ps}"
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

# Resolve bound driver sysfs dir (snd_pci_ps, snd_acp_pci, …).
pci_driver_name() {
	local link name
	link="$(readlink "${PCI_SYS:-$(pci_sysfs)}/driver" 2>/dev/null)" || return 1
	name="$(basename "$link")"
	[[ -n "$name" ]] || return 1
	echo "$name"
}

pci_driver_dir() {
	local name dir
	name="$(pci_driver_name 2>/dev/null)" || return 1
	dir="/sys/bus/pci/drivers/${name}"
	[[ -d "$dir" ]] || return 1
	echo "$dir"
}

pci_driver_status() {
	local sys drv name
	sys="$(pci_sysfs)"
	if name="$(pci_driver_name 2>/dev/null)"; then
		echo "bound driver=${name} dir=/sys/bus/pci/drivers/${name}"
		return 0
	fi
	if [[ -d "/sys/bus/pci/drivers/snd_pci_ps" ]]; then
		echo "unbound (snd_pci_ps driver registered, device not bound)"
		return 0
	fi
	echo "no driver (snd_pci_ps sysfs missing — module likely unloaded)"
	return 1
}

pci_write() {
	timeout 30 sh -c "echo '$1' > '$2'" 2>/dev/null
}

# PX13 PCI reset — from px13-audio-fix (longer bind wait, FW settle).
pci_reset_acp() {
	local drv

	stop_pipewire_all
	sleep 1

	if ! drv="$(pci_driver_dir 2>/dev/null)"; then
		pci_driver_status >&2 || true
		if [[ -d "/sys/bus/pci/drivers/snd_pci_ps" ]]; then
			drv="/sys/bus/pci/drivers/snd_pci_ps"
			log "pci_reset: device unbound — bind via ${drv}"
		else
			log "pci_reset: driver sysfs missing (modprobe snd_pci_ps first, or use pci_remove_rescan)"
			return 1
		fi
	fi

	if [[ ! -e "${drv}/${PCI_DEV}" ]]; then
		log "pci_reset: bind only $PCI_DEV → $(basename "$drv")"
		pci_write "$PCI_DEV" "${drv}/bind" || true
	else
		log "pci_reset: unbind $PCI_DEV from $(basename "$drv")"
		if ! pci_write "$PCI_DEV" "${drv}/unbind"; then
			log "pci_reset: unbind failed/timed out"
			return 1
		fi
		sleep 2
		log "pci_reset: bind $PCI_DEV"
		pci_write "$PCI_DEV" "${drv}/bind" || true
	fi

	local _
	for _ in $(seq 1 80); do
		[[ -e "${drv}/${PCI_DEV}" ]] && grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && return 0
		sleep 0.25
	done
	log "pci_reset: card did not reappear"
	return 1
}

# Layer 4: full PCI re-enumeration (distinct from unbind).
pci_remove_rescan() {
	local dev
	dev="$(pci_sysfs)"
	[[ -w "${dev}/remove" ]] || {
		log "pci_remove_rescan: ${dev}/remove not writable"
		return 1
	}
	log "pci_remove_rescan: remove $PCI_DEV (HIGH RISK — reboot if device missing)"
	echo 1 >"${dev}/remove"
	sleep 2
	echo 1 >/sys/bus/pci/rescan
	sleep 5
	local _
	for _ in $(seq 1 60); do
		[[ -d "$(pci_sysfs)" ]] && grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && return 0
		sleep 0.5
	done
	log "pci_remove_rescan: device or card did not return"
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
		reason="post-resume audio broken (S2 symptom — card present, ALSA hw fail)"
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
		witness_playback_alsa_hw_primary && pb=ok
		if [[ "$pb" == ok && "$uspace" != dummy && "$uspace" != none && "$dummy_default" -eq 0 ]]; then
			reason="suspend ok; real audio still works — bug not reproduced this cycle"
		else
			w=2
			reason="post-resume broken (alsa_hw=${pb}, plughw=$(witness_playback_alsa_plughw && echo ok || echo fail), userspace=${uspace}, dummy_default=${dummy_default})"
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

# Direct ALSA device — default hw (not plughw). plughw only resamples; does not prove DSP path.
alsa_speaker_dev() {
	local card pcm
	if [[ -n "${PX13_ALSA_DEV:-}" ]]; then
		echo "$PX13_ALSA_DEV"
		return 0
	fi
	card="$(alsa_card_number)"
	[[ -n "$card" ]] || return 1
	pcm="${PX13_ALSA_PCM:-2}"
	echo "hw:${card},${pcm}"
}

alsa_plughw_dev() {
	local dev card pcm
	dev="$(alsa_speaker_dev)" || return 1
	card="${dev#hw:}"
	card="${card%%,*}"
	pcm="${dev##*,}"
	echo "plughw:${card},${pcm}"
}

alsa_card_present() {
	grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null
}

_USERSPACE_PACTL="${USERSPACE_PACTL:-/usr/bin/pactl}"
_USERSPACE_WPCTL="${USERSPACE_WPCTL:-/usr/bin/wpctl}"

# Run a command in the first logged-in user's PipeWire session (fail closed when absent).
userspace_as_user() {
	local uid user_name runtime_dir
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		runtime_dir="/run/user/$uid"
		[[ -d "$runtime_dir" ]] || continue
		sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" "$@"
		return $?
	done
	return 1
}

# aplay -l must expose the amd-soundwire PCM (not only /proc/asound/cards).
witness_aplay_list_ok() {
	command -v aplay >/dev/null 2>&1 || return 1
	aplay -l 2>/dev/null | grep -qiE 'amd-soundwire|amdsoundwire|ProArt'
}

alsa_hw_dev() {
	alsa_speaker_dev
}

# SmartAmp (hw:1,2) may reject sine params (EINVAL) while wav works — use raw aplay probe.
_witness_speaker_test_sec() {
	echo "${PX13_SPEAKER_TEST_TIMEOUT:-8}"
}

# --- PCM granular witness (set_params vs playback; stderr capture) ---
export WITNESS_PCM_LAST_DEV=""
export WITNESS_PCM_LAST_RC=0
export WITNESS_PCM_LAST_ERR=""
export WITNESS_PCM_LAST_CLASS=""

witness_pcm_classify_err() {
	local err="$1"
	if [[ -z "$err" ]]; then
		echo open_ok
	elif echo "$err" | grep -qiE 'set_params|Imposible instalar|unable to install hw|cannot set hw'; then
		echo set_params_fail
	elif echo "$err" | grep -qiE 'busy|Device or resource busy'; then
		echo busy
	elif echo "$err" | grep -qiE 'ENODEV|No such file'; then
		echo nodev
	elif echo "$err" | grep -qiE 'EINVAL|Argumento inválido|Invalid argument'; then
		echo einval
	elif echo "$err" | grep -qiE 'EIO|Input/output error'; then
		echo eio
	elif echo "$err" | grep -qiE 'ENXIO'; then
		echo enxio
	else
		echo other
	fi
}

_witness_pcm_run() {
	local dev="$1"
	shift
	local errfile rc
	errfile="$(mktemp)"
	if [[ "$(id -u)" -eq 0 ]] && userspace_as_user true 2>/dev/null; then
		userspace_as_user timeout "$(_witness_speaker_test_sec)" "$@" 2>"$errfile" || rc=$?
	else
		timeout "$(_witness_speaker_test_sec)" "$@" 2>"$errfile" || rc=$?
	fi
	rc="${rc:-0}"
	export WITNESS_PCM_LAST_DEV="$dev"
	export WITNESS_PCM_LAST_RC="$rc"
	export WITNESS_PCM_LAST_ERR="$(tr '\n' ' ' <"$errfile" | sed 's/  */ /g')"
	rm -f "$errfile"
	export WITNESS_PCM_LAST_CLASS="$(witness_pcm_classify_err "$WITNESS_PCM_LAST_ERR")"
	[[ "${WITNESS_PCM_VERBOSE:-0}" == "1" && -n "$WITNESS_PCM_LAST_ERR" ]] && \
		printf '%s\n' "$WITNESS_PCM_LAST_ERR" >&2
	return "$rc"
}

# Try aplay open+set_params+1s IO. Returns 0 only on full success.
witness_pcm_try_aplay() {
	local dev="$1"
	command -v aplay >/dev/null 2>&1 || return 1
	_witness_pcm_run "$dev" aplay -D "$dev" -f S16_LE -c 2 -r 48000 -t raw -d 1 -q /dev/zero
}

witness_pcm_try_speaker_test() {
	local dev="$1"
	command -v speaker-test >/dev/null 2>&1 || return 1
	_witness_pcm_run "$dev" speaker-test -D "$dev" -c2 -r48000 -F S16_LE -t wav -l 1
}

# Playback PCM indices for card N from /proc/asound/pcm.
witness_pcm_list_playback() {
	local card="${1:-$(alsa_card_number)}"
	[[ -n "$card" ]] || return 1
	awk -v c="$(printf '%02d' "$card")" '
		$1 ~ /^[0-9]+-/ {
			split($1, a, "-")
			if (a[1] == c && $0 ~ /playback/) {
				split(a[2], b, ":")
				print b[1] + 0
			}
		}
	' /proc/asound/pcm 2>/dev/null
}

witness_pcm_sysfs_dump() {
	local card="$1" pcm="$2" f base
	base="/proc/asound/card${card}/pcm${pcm}p/sub0"
	for f in info status hw_params sw_params; do
		echo "--- ${base}/${f} ---"
		if [[ -r "${base}/${f}" ]]; then
			cat "${base}/${f}" 2>/dev/null || echo "(unreadable)"
		else
			echo "(missing)"
		fi
		echo
	done
}

witness_pcm_hw_opens() {
	witness_pcm_try_aplay "$1"
}

witness_playback_alsa_hw_on_dev() {
	local dev="$1"
	if [[ "${PX13_SPEAKER_TEST_MODE:-aplay}" == wav ]]; then
		_witness_speaker_test_cmd "$dev" wav >/dev/null 2>&1 && return 0
		return 1
	fi
	witness_pcm_hw_opens "$dev"
}

# Primary PCM only (SmartAmp hw:1,2) — authoritative for S2 gates.
witness_playback_alsa_hw_primary() {
	local dev
	dev="$(alsa_hw_dev)" || return 1
	witness_playback_alsa_hw_on_dev "$dev"
}

# Any speaker playback path (primary then SimpleJack hw:1,0).
witness_playback_alsa_hw() {
	local dev card pcm
	dev="$(alsa_hw_dev)" || return 1
	witness_playback_alsa_hw_on_dev "$dev" && return 0
	card="${dev#hw:}"
	card="${card%%,*}"
	pcm="${dev##*,}"
	[[ "$pcm" != "2" ]] && return 1
	witness_playback_alsa_hw_on_dev "hw:${card},0"
}

witness_playback_alsa_plughw() {
	local dev
	dev="$(alsa_plughw_dev)" || return 1
	witness_playback_alsa_hw_on_dev "$dev"
}

# Prefer session user for ALSA open (root/sudo often fails while desktop user passes).
_witness_speaker_test_cmd() {
	local dev="$1" mode="${2:-wav}"
	local sec
	sec="$(_witness_speaker_test_sec)"
	if ! command -v speaker-test >/dev/null 2>&1; then
		return 1
	fi
	if [[ "$(id -u)" -eq 0 ]] && userspace_as_user true 2>/dev/null; then
		userspace_as_user timeout "$sec" \
			speaker-test -D "$dev" -c2 -t wav -l 1 -r 48000
	else
		timeout "$sec" speaker-test -D "$dev" -c2 -t wav -l 1 -r 48000
	fi
}
witness_aplay_wav_hw() {
	local dev wav="${PX13_ALSA_WAV:-/usr/share/sounds/alsa/Front_Center.wav}"
	command -v aplay >/dev/null 2>&1 || return 1
	[[ -f "$wav" ]] || return 1
	dev="$(alsa_hw_dev)" || return 1
	if [[ "$(id -u)" -eq 0 ]] && userspace_as_user true 2>/dev/null; then
		userspace_as_user timeout 8 aplay -D "$dev" -c2 -q "$wav" >/dev/null 2>&1
	else
		timeout 8 aplay -D "$dev" -c2 -q "$wav" >/dev/null 2>&1
	fi
}

_userspace_sink_name_real() {
	local name="$1"
	[[ -n "$name" ]] || return 1
	echo "$name" | grep -qi dummy && return 1
	echo "$name" | grep -qiE 'speaker|proart|alsa|amdsoundwire|PX13|Audio Coprocessor|analog' && return 0
	# Any non-dummy sink counts (WirePlumber naming varies).
	return 0
}

# Returns: real | dummy | none | no_session
userspace_sink_presence_quality() {
	local uid user_name runtime_dir sinks line name
	if [[ -x "$_USERSPACE_PACTL" ]]; then
		for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
			user_name="$(id -nu "$uid" 2>/dev/null)" || continue
			runtime_dir="/run/user/$uid"
			[[ -d "$runtime_dir" ]] || continue
			sinks="$(sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
				"$_USERSPACE_PACTL" list sinks short 2>/dev/null || true)"
			[[ -z "$sinks" ]] && { echo none; return 0; }
			while IFS= read -r line; do
				[[ -z "$line" ]] && continue
				name="${line#*$'\t'}"
				name="${name%%$'\t'*}"
				_userspace_sink_name_real "$name" && { echo real; return 0; }
			done <<<"$sinks"
			echo dummy
			return 0
		done
	fi
	if [[ -x "$_USERSPACE_WPCTL" ]] && userspace_as_user "$_USERSPACE_WPCTL" status &>/dev/null; then
		local out has_real=0 has_dummy=0 in_sinks=0 line name
		out="$(userspace_as_user "$_USERSPACE_WPCTL" status 2>/dev/null || true)"
		while IFS= read -r line; do
			[[ "$line" =~ Sinks: ]] && in_sinks=1 && continue
			[[ "$in_sinks" == 1 && "$line" =~ ^[[:space:]]*(├|└)─[[:space:]]*(Sources|Filters|Streams): ]] && break
			[[ "$in_sinks" != 1 ]] && continue
			[[ "$line" =~ │[[:space:]]+\*?[[:space:]]+[0-9]+\.[[:space:]]+(.+) ]] || continue
			name="${BASH_REMATCH[1]}"
			name="${name%%[[:space:]]*\[*}"
			if echo "$name" | grep -qi dummy; then
				has_dummy=1
			else
				has_real=1
			fi
		done <<<"$out"
		[[ "$has_real" -eq 1 ]] && { echo real; return 0; }
		[[ "$has_dummy" -eq 1 ]] && { echo dummy; return 0; }
		echo none
		return 0
	fi
	echo no_session
}

# Returns: real | dummy | none | no_session
userspace_default_sink_quality() {
	local uid user_name runtime_dir default out line name
	if [[ -x "$_USERSPACE_PACTL" ]]; then
		for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
			user_name="$(id -nu "$uid" 2>/dev/null)" || continue
			runtime_dir="/run/user/$uid"
			[[ -d "$runtime_dir" ]] || continue
			default="$(sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
				"$_USERSPACE_PACTL" get-default-sink 2>/dev/null || true)"
			[[ -z "$default" ]] && { echo none; return 0; }
			echo "$default" | grep -qi dummy && { echo dummy; return 0; }
			echo real
			return 0
		done
	fi
	if [[ -x "$_USERSPACE_WPCTL" ]] && userspace_as_user "$_USERSPACE_WPCTL" status &>/dev/null; then
		local out in_sinks=0 line name
		out="$(userspace_as_user "$_USERSPACE_WPCTL" status 2>/dev/null || true)"
		while IFS= read -r line; do
			[[ "$line" =~ Sinks: ]] && in_sinks=1 && continue
			[[ "$in_sinks" == 1 && "$line" =~ ^[[:space:]]*(├|└)─[[:space:]]*(Sources|Filters|Streams): ]] && break
			[[ "$in_sinks" != 1 ]] && continue
			[[ "$line" =~ │[[:space:]]+\*[[:space:]]+[0-9]+\.[[:space:]]+(.+) ]] || continue
			name="${BASH_REMATCH[1]}"
			name="${name%%[[:space:]]*\[*}"
			echo "$name" | grep -qi dummy && { echo dummy; return 0; }
			echo real
			return 0
		done <<<"$out"
		echo none
		return 0
	fi
	echo no_session
}

userspace_wpctl_summary() {
	local out
	[[ -x "$_USERSPACE_WPCTL" ]] || { echo unavailable; return 0; }
	out="$(userspace_as_user "$_USERSPACE_WPCTL" status 2>/dev/null || true)"
	echo "$out" | awk '/^Audio$/,/^Video$/ { print }' | grep -E 'Devices:|Sinks:|│' | head -20 | tr '\n' ';' | sed 's/;$/\n/'
}

# Logged-in PipeWire/Pulse sink state (post-suspend may be dummy-only or empty).
userspace_sink_state() {
	local q
	q="$(userspace_sink_presence_quality)"
	case "$q" in
	real) echo ok ;;
	dummy) echo dummy ;;
	none | no_session) echo "$q" ;;
	*) echo unknown ;;
	esac
}

userspace_audio_broken() {
	local st
	st="$(userspace_sink_state)"
	[[ "$st" == dummy || "$st" == none || "$st" == no_session ]]
}

userspace_default_sink_is_dummy() {
	[[ "$(userspace_default_sink_quality)" == dummy ]]
}

userspace_default_sink_is_real() {
	[[ "$(userspace_default_sink_quality)" == real ]]
}

userspace_real_sink_present() {
	[[ "$(userspace_sink_presence_quality)" == real ]]
}

# plughw speaker-test (legacy name — prefer witness_playback_alsa_plughw).
witness_playback_alsa() {
	witness_playback_alsa_plughw
}

# S2: card present but primary SmartAmp PCM broken (hw:1,2).
post_resume_audio_broken() {
	alsa_card_present || return 1
	witness_playback_alsa_hw_primary && return 1
	userspace_audio_broken && return 0
	userspace_default_sink_is_dummy && return 0
	return 0
}

# Strict playback: primary PCM functional AND no Dummy/none userspace.
witness_playback() {
	local uid user_name runtime_dir

	if alsa_card_present; then
		witness_playback_alsa_hw_primary || return 1
		userspace_default_sink_is_dummy && return 1
		userspace_audio_broken && return 1
		return 0
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

# S0 health: kernel card + ALSA **hw** playback (not plughw alone).
confirm_s0_health() {
	if ! alsa_card_present; then
		log "S0 FAIL: no $CARD_MATCH in /proc/asound/cards"
		return 1
	fi
	if witness_playback_alsa_hw_primary; then
		log "S0 OK: amd-soundwire + primary PCM (${PX13_ALSA_DEV:-$(alsa_hw_dev)})"
		return 0
	fi
	if [[ "${RESOLUTION_S0_ALSA_ONLY:-0}" == "1" ]]; then
		log "S0 OK (alsa-only): card present, hw playback skipped"
		return 0
	fi
	log "S0 FAIL: primary PCM failed (dev=$(alsa_hw_dev 2>/dev/null || echo ?); fallback=$(witness_playback_alsa_hw && echo ok || echo fail); sink=$(userspace_sink_state))"
	log "hint: test as session user — speaker-test -D $(alsa_hw_dev 2>/dev/null || echo hw:?,?)"
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
