#!/usr/bin/env bash
#
# Recover ASUS ProArt PX13 internal-speaker audio (snd_repair hardened fork).
# Drop-in replacement for brainchillz /usr/local/sbin/px13-audio-fix.sh
#
# Changes vs upstream brainchillz:
#   - Stop PipeWire/WirePlumber BEFORE PCI reset (avoids hw_params hammering :8)
#   - Non-blocking stop with timeout + SIGKILL (avoids 90s systemctl hang)
#   - Skip PCI bind when unbind fails (reduces soft-lockup risk)
#   - Wait for async TAS2783 FW before restarting userspace audio
#   - Optional ALSA UCM HiFi verb + second PCI reset on FW failure
#
# Env overrides:
#   PX13_PCI_DEV=0000:c4:00.5
#   PX13_FW_SETTLE_SEC=12       seconds after card probe before FW check
#   PX13_FW_PROBE_RETRIES=2     PCI reset attempts if FW still broken
#   PX13_PIPEWIRE_STOP_SEC=12   stop timeout per user before SIGKILL
#   PX13_SKIP_UCM=1             skip alsaucm HiFi
#   PX13_SKIP_PIPEWIRE=1        skip pipewire stop/start (debug)

set -uo pipefail

PCI_DEV="${PX13_PCI_DEV:-0000:c4:00.5}"
PCI_DRV="/sys/bus/pci/drivers/snd_pci_ps"
CARD_MATCH="amd-soundwire"
ALSA_CARD_RE='ASUSTeKCOMPUTERINC\.-ProArtPX13'
FW_SETTLE_SEC="${PX13_FW_SETTLE_SEC:-12}"
FW_PROBE_RETRIES="${PX13_FW_PROBE_RETRIES:-2}"
PW_STOP_SEC="${PX13_PIPEWIRE_STOP_SEC:-12}"
SKIP_UCM="${PX13_SKIP_UCM:-0}"
SKIP_PIPEWIRE="${PX13_SKIP_PIPEWIRE:-0}"
LOCK_FILE="${PX13_LOCK_FILE:-/run/px13-audio-fix.lock}"
SND_REPAIR_REPO="${SND_REPAIR_REPO:-/home/rutrus/snd_repair}"

log() { echo "px13-audio-fix: $*"; }

acquire_lock() {
	exec 9>"$LOCK_FILE"
	if ! flock -n 9; then
		log "another instance is running — exiting"
		exit 0
	fi
}

recent_resume_pm110() {
	command -v journalctl >/dev/null 2>&1 || return 1
	journalctl -k -b 0 --no-pager --since '3 min ago' 2>/dev/null \
		| grep -qE '0102:0000:01:(8|b).*failed to resume: error -110'
}

schedule_fw_validation() {
	local hook="${SND_REPAIR_REPO}/scripts/fw-validation-suspend-hook.sh"
	[[ -x "$hook" ]] || return 0
	"$hook" 2>/dev/null || true
}

for_each_logged_in_user() {
	local fn="$1"
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		user_name="$(id -nu "$uid" 2>/dev/null)" || continue
		"$fn" "$uid" "$user_name"
	done
}

pci_write() {
	timeout 30 sh -c "echo '$1' > '$2'" 2>/dev/null
}

session_frozen() {
	local uid="$1"
	local events="/sys/fs/cgroup/user.slice/user-${uid}.slice/cgroup.events"
	[[ -r "$events" ]] && grep -q '^frozen 1$' "$events" 2>/dev/null
}

stop_pipewire_user() {
	local uid="$1"
	local user_name="$2"
	local runtime_dir="/run/user/$uid"
	local units=(
		wireplumber pipewire-pulse pipewire
		pipewire.socket pipewire-pulse.socket
		filter-chain.service
	)

	[[ -d "$runtime_dir" ]] || return 0
	session_frozen "$uid" && {
		log "uid $uid ($user_name) frozen — pipewire stop skipped"
		return 0
	}

	log "stopping pipewire (+ sockets) for uid $uid ($user_name)"
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user stop "${units[@]}" 2>/dev/null &
	local stop_pid=$!
	local i
	for ((i = 1; i <= PW_STOP_SEC; i++)); do
		if ! sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
			systemctl --user is-active --quiet pipewire pipewire.socket 2>/dev/null; then
			wait "$stop_pid" 2>/dev/null || true
			return 0
		fi
		sleep 1
	done
	wait "$stop_pid" 2>/dev/null || true
	log "pipewire stop timed out for uid $uid — SIGKILL"
	pkill -KILL -u "$user_name" wireplumber 2>/dev/null || true
	pkill -KILL -u "$user_name" pipewire 2>/dev/null || true
	pkill -KILL -u "$user_name" pipewire-pulse 2>/dev/null || true
	# Evitar reactivación por socket antes del reset PCI
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user mask --runtime pipewire.socket pipewire-pulse.socket 2>/dev/null \
		|| true
	sleep 1
}

start_pipewire_user() {
	local uid="$1"
	local user_name="$2"
	local runtime_dir="/run/user/$uid"

	[[ -d "$runtime_dir" ]] || return 0
	session_frozen "$uid" && {
		log "uid $uid ($user_name) frozen — pipewire start deferred to thaw/udev"
		return 0
	}

	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user unmask pipewire.socket pipewire-pulse.socket 2>/dev/null \
		|| true

	log "starting pipewire for uid $uid ($user_name)"
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null \
		|| log "pipewire start for uid $uid failed"
}

ucm_card_name() {
	awk '/ProArtPX13/ {gsub(/^[[:space:]]+/, ""); print; exit}' /proc/asound/cards 2>/dev/null
}

apply_ucm_hifi() {
	[[ "$SKIP_UCM" == "1" ]] && return 0
	local card
	card="$(ucm_card_name)"
	[[ -n "$card" ]] || {
		log "UCM card name not found — skipping HiFi verb"
		return 0
	}
	if command -v alsaucm >/dev/null 2>&1; then
		log "alsaucm set _verb HiFi ($card)"
		alsaucm -c "$card" set _verb HiFi 2>/dev/null \
			|| log "alsaucm HiFi failed (non-fatal)"
	else
		log "alsaucm not installed — skipping HiFi verb"
	fi
}

kmsg_since() {
	local marker="$1"
	if command -v journalctl >/dev/null 2>&1; then
		journalctl -k -b 0 --no-pager --since "$marker" 2>/dev/null || true
	else
		dmesg 2>/dev/null || true
	fi
}

fw_broken_since() {
	local marker="$1"
	kmsg_since "$marker" | grep -qE '0102:0000:01:(8|b).*(playback without fw|FW download failed|fw download wait timeout)'
}

probe_fw_once() {
	local dev="${PX13_ALSA_DEV:-plughw:1,2}"
	command -v speaker-test >/dev/null 2>&1 || return 0
	timeout 6 speaker-test -D "$dev" -c 2 -t pink -l 1 -r 48000 >/dev/null 2>&1
}

check_fw_after_reset() {
	local marker="$1"

	log "waiting ${FW_SETTLE_SEC}s for async FW download"
	sleep "$FW_SETTLE_SEC"

	if fw_broken_since "$marker"; then
		log "kernel already reports FW errors before probe"
		return 1
	fi

	if command -v speaker-test >/dev/null 2>&1; then
		if probe_fw_once; then
			if fw_broken_since "$marker"; then
				log "speaker-test triggered FW errors"
				return 1
			fi
			log "speaker-test probe OK"
			return 0
		fi
		log "speaker-test probe failed"
		return 1
	fi

	# Sin speaker-test: solo ausencia de errores tras settle
	if fw_broken_since "$marker"; then
		return 1
	fi
	log "no FW errors in kernel log (speaker-test not installed)"
	return 0
}

pci_reset() {
	local unbind_ok=1

	if [[ ! -d "$PCI_DRV" ]]; then
		log "snd_pci_ps driver not present — skipping PCI reset"
		return 1
	fi

	if [[ ! -e "$PCI_DRV/$PCI_DEV" ]]; then
		log "PCI $PCI_DEV not bound — bind only"
		pci_write "$PCI_DEV" "$PCI_DRV/bind" || {
			log "bind failed/timed out"
			return 1
		}
	else
		log "unbinding PCI $PCI_DEV"
		if ! pci_write "$PCI_DEV" "$PCI_DRV/unbind"; then
			log "unbind failed/timed out — skipping bind (avoid bus lockup)"
			return 1
		fi
		sleep 2
		log "binding PCI $PCI_DEV"
		pci_write "$PCI_DEV" "$PCI_DRV/bind" || {
			log "bind failed/timed out"
			return 1
		}
	fi

	local _
	for _ in $(seq 1 40); do
		if grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null; then
			log "amd-soundwire card is present"
			return 0
		fi
		sleep 0.25
	done

	log "WARNING: amd-soundwire card did not reappear"
	return 1
}

# --- main ---------------------------------------------------------------------

acquire_lock

if recent_resume_pm110; then
	log "SDW resume -110 detected — extra settle + 3rd PCI attempt"
	FW_SETTLE_SEC=$((FW_SETTLE_SEC + 8))
	FW_PROBE_RETRIES=3
fi

if [[ "$SKIP_PIPEWIRE" != "1" ]]; then
	for_each_logged_in_user stop_pipewire_user
fi

fw_ok=0
for ((reset_try = 1; reset_try <= FW_PROBE_RETRIES; reset_try++)); do
	log "PCI reset attempt ${reset_try}/${FW_PROBE_RETRIES}"

	if ! pci_reset; then
		log "PCI reset failed on attempt ${reset_try}"
		sleep 3
		continue
	fi

	marker="$(date -Is)"
	if check_fw_after_reset "$marker"; then
		fw_ok=1
		break
	fi
	log "FW not ready — retrying PCI reset"
	sleep 2
done

if [[ "$fw_ok" -ne 1 ]]; then
	log "WARNING: TAS2783 FW broken (:8/:b) — cold reboot required for speakers"
	if [[ "$SKIP_PIPEWIRE" != "1" ]]; then
		log "restoring PipeWire (may show Dummy until reboot)"
		for_each_logged_in_user start_pipewire_user
	fi
	schedule_fw_validation
	exit 1
fi

apply_ucm_hifi

if [[ "$SKIP_PIPEWIRE" != "1" ]]; then
	for_each_logged_in_user start_pipewire_user
fi

schedule_fw_validation
log "done"
exit 0
