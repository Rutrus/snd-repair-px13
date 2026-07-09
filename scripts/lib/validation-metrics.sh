#!/usr/bin/env bash
# Shared metrics for composite PASS/WARN (kernel + userspace).
# Source from other scripts: . "$(dirname "$0")/lib/validation-metrics.sh"

validation_metrics_init() {
	VM_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	VM_SDW_UID8="/sys/bus/soundwire/devices/sdw:0:1:0102:0000:01:8/status"
	VM_SDW_UIDB="/sys/bus/soundwire/devices/sdw:0:1:0102:0000:01:b/status"
	VM_SDW_RT721="/sys/bus/soundwire/devices/sdw:0:1:025d:0721:01/status"
}

vm_sdw_status() {
	local path="$1"
	if [[ -r "$path" ]]; then
		tr -d '[:space:]' <"$path"
	else
		echo "MISSING"
	fi
}

vm_kmsg_since() {
	local since="${1:-}"
	if [[ -n "$since" ]]; then
		journalctl -k -b 0 --no-pager --since "$since" 2>/dev/null || true
	else
		journalctl -k -b 0 --no-pager 2>/dev/null || true
	fi
}

vm_pm_since_resume() {
	local since="$1"
	local k
	k="$(vm_kmsg_since "$since")"
	if printf '%s\n' "$k" | grep -qE 'failed to resume: error -110'; then
		echo "FAIL"
	elif printf '%s\n' "$k" | grep -qE 'Initialization not complete, timed out'; then
		echo "FAIL"
	else
		echo "OK"
	fi
}

vm_phase5_latest() {
	local uid="$1" field="$2"
	journalctl -k -b 0 --no-pager -g "PHASE5.*uid=0x${uid}" 2>/dev/null \
		| grep "update_status_" | tail -1 \
		| sed -n "s/.*${field}=\([0-9]*\).*/\1/p"
}

vm_uid_fw_from_kmsg() {
	local uid="$1" since="${2:-}"
	local k pb fail
	k="$(vm_kmsg_since "$since")"
	fail="$(printf '%s\n' "$k" | grep -cE "0102:0000:01:${uid}.*FW download failed" || true)"
	pb="$(printf '%s\n' "$k" | grep -cE "0102:0000:01:${uid}.*playback without fw" || true)"
	if [[ "$fail" -gt 0 ]]; then
		echo "FAIL"
	elif [[ "$pb" -gt 0 ]]; then
		echo "NO"
	else
		local fw_ok
		fw_ok="$(vm_phase5_latest "$uid" fw_ok)"
		if [[ "$fw_ok" == "1" ]]; then
			echo "YES"
		else
			echo "UNK"
		fi
	fi
}

vm_attach_label() {
	local sysfs="$1"
	local st
	st="$(vm_sdw_status "$sysfs")"
	case "$st" in
	Attached) echo "YES" ;;
	Unattached) echo "NO" ;;
	*) echo "UNK" ;;
	esac
}

vm_pipewire_active() {
	if systemctl --user is-active --quiet pipewire 2>/dev/null \
		&& systemctl --user is-active --quiet wireplumber 2>/dev/null; then
		echo "YES"
	else
		echo "NO"
	fi
}

vm_default_sink() {
	local out
	out="$(XDG_RUNTIME_DIR="${VM_XDG}" wpctl status 2>/dev/null \
		| awk '/Sinks:/{s=1;next} /Sources:/{s=0} s && /\*/{print; exit}')"
	if [[ -z "$out" ]]; then
		echo "NONE"
		return
	fi
	if echo "$out" | grep -qi dummy; then
		echo "Dummy"
	elif echo "$out" | grep -qi 'Audio Coprocessor\|Speaker\|SmartAmp'; then
		echo "Speaker"
	elif echo "$out" | grep -qi hdmi; then
		echo "HDMI"
	else
		echo "$out" | sed 's/.*\.[[:space:]]*//' | awk '{$1=$1};1' | cut -c1-40
	fi
}

vm_speaker_present() {
	local s
	s="$(vm_default_sink)"
	case "$s" in
	Speaker) echo "YES" ;;
	Dummy|NONE) echo "NO" ;;
	*) echo "UNK" ;;
	esac
}

vm_runtime_status() {
	local dev="$1"
	local p="/sys/bus/soundwire/devices/${dev}/power/runtime_status"
	[[ -r "$p" ]] && cat "$p" || echo "MISSING"
}

vm_playback_without_fw_count() {
	local since="${1:-}"
	vm_kmsg_since "$since" | grep -cE '0102:0000:01:8.*playback without fw' || true
}

vm_speaker_test_ok() {
	local dev="${ALSA_DEV:-plughw:1,2}"
	local dur="${SPEAKER_TEST_SEC:-1}"
	if ! command -v speaker-test >/dev/null 2>&1; then
		echo "SKIP"
		return
	fi
	if timeout "$((dur + 2))" speaker-test -D "$dev" -c 2 -t wav -l 1 -s 1 >/dev/null 2>&1; then
		echo "YES"
	else
		echo "NO"
	fi
}

vm_composite_result() {
	local pm="$1" attach8="$2" fw8="$3" speaker="$4" audio="$5"
	if [[ "$pm" == "OK" && "$attach8" == "YES" && "$fw8" == "YES" \
		&& "$speaker" == "YES" && "$audio" == "YES" ]]; then
		echo "PASS"
	else
		echo "WARN"
	fi
}

vm_collect_snapshot() {
	local offset_s="$1" since_resume="$2"
	validation_metrics_init
	local pm attach8 attachb attach721 fw8 fwb pw sink speaker pb rt8 rtb rt721 audio result
	pm="$(vm_pm_since_resume "$since_resume")"
	attach8="$(vm_attach_label "$VM_SDW_UID8")"
	attachb="$(vm_attach_label "$VM_SDW_UIDB")"
	attach721="$(vm_attach_label "$VM_SDW_RT721")"
	fw8="$(vm_uid_fw_from_kmsg 8 "$since_resume")"
	fwb="$(vm_uid_fw_from_kmsg b "$since_resume")"
	pw="$(vm_pipewire_active)"
	sink="$(vm_default_sink)"
	speaker="$(vm_speaker_present)"
	pb="$(vm_playback_without_fw_count "$since_resume")"
	rt8="$(vm_runtime_status 'sdw:0:1:0102:0000:01:8')"
	rtb="$(vm_runtime_status 'sdw:0:1:0102:0000:01:b')"
	rt721="$(vm_runtime_status 'sdw:0:1:025d:0721:01')"
	audio="$(vm_speaker_test_ok)"
	result="$(vm_composite_result "$pm" "$attach8" "$fw8" "$speaker" "$audio")"
	printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
		"$offset_s" "$pm" "$attach8" "$attachb" "$attach721" \
		"$fw8" "$fwb" "$pw" "$sink" "$speaker" "$pb" "$rt8" "$rtb" "$rt721" "$audio" "$result"
}

vm_dump_snapshot_verbose() {
	local dir="$1" offset_s="$2" since_resume="$3"
	mkdir -p "$dir"
	validation_metrics_init
	{
		echo "=== offset=${offset_s}s since_resume=${since_resume} $(date -Is) ==="
		echo "--- wpctl status ---"
		XDG_RUNTIME_DIR="${VM_XDG}" wpctl status 2>&1 || true
		echo "--- pw-cli ls Node ---"
		XDG_RUNTIME_DIR="${VM_XDG}" pw-cli ls Node 2>&1 | head -40 || true
		echo "--- aplay -l ---"
		aplay -l 2>&1 || true
		echo "--- SDW sysfs status ---"
		for p in "$VM_SDW_UID8" "$VM_SDW_UIDB" "$VM_SDW_RT721"; do
			printf '%s: ' "$p"
			vm_sdw_status "$p" 2>/dev/null || echo MISSING
		done
		echo "--- dmesg since resume (tail) ---"
		vm_kmsg_since "$since_resume" | tail -30
	} >"${dir}/t$(printf '%03d' "$offset_s")s.txt"
}
