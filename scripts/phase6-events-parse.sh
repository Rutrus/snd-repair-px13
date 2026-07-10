#!/usr/bin/env bash
# Parse three layered chronologies since resume → validation/phase6-events.csv
# Layers: hardware | kernel | userspace
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REPO}/validation/phase6-events.csv"
RUN_ID="${1:?run_id}"
RESUME_TS="${2:?resume_ts}"

RESUME_EPOCH="$(date -d "$RESUME_TS" +%s 2>/dev/null || date -d "${RESUME_TS/T/ }" +%s)"
ANCHOR="$(journalctl -k -b 0 --no-pager -g 'PM: suspend exit' 2>/dev/null | tail -1)"
ANCHOR_TS="$(echo "$ANCHOR" | awk '{print $1,$2,$3}')"
[[ -n "$ANCHOR_TS" && "$ANCHOR_TS" != "  " ]] && \
	RESUME_EPOCH="$(date -d "$ANCHOR_TS" +%s 2>/dev/null || echo "$RESUME_EPOCH")"

[[ -f "$OUT" ]] || echo "run_id,offset_ms,layer,component,event,detail" >"$OUT"

offset_ms_from_line() {
	local line="$1"
	local ts epoch
	ts="$(echo "$line" | awk '{print $1,$2,$3}')"
	epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
	echo $(( (epoch - RESUME_EPOCH) * 1000 ))
}

append_ev() {
	local off="$1" layer="$2" comp="$3" ev="$4" detail="$5"
	printf '%s,%s,%s,%s,%s,%s\n' "$RUN_ID" "$off" "$layer" "$comp" "$ev" \
		"$(echo "$detail" | tr ',' ';' | head -c 240)" >>"$OUT"
}

# shellcheck source=lib/phase6-journal.sh
. "${REPO}/scripts/lib/phase6-journal.sh"
REPO_ROOT="$REPO"
bounds="$(phase6_resume_window_bounds "$RESUME_TS")"
JOURNAL_SINCE="${bounds%%$'\t'*}"
JOURNAL_UNTIL="${bounds#*$'\t'}"

classify_kernel_line() {
	local off="$1" body="$2"

	if echo "$body" | grep -q 'PM: suspend exit'; then
		append_ev "$off" kernel PM suspend_exit "$body"
	elif echo "$body" | grep -q 'PM: suspend entry'; then
		append_ev "$off" kernel PM suspend_entry "$body"
	elif echo "$body" | grep -q 'snd_pci_ps' && echo "$body" | grep -qiE 'resume|enable|probe'; then
		append_ev "$off" hardware acp_pci resume "$body"
	elif echo "$body" | grep -q 'snd_pci_ps.*IO_PAGE_FAULT'; then
		append_ev "$off" hardware acp io_page_fault "$body"
	elif echo "$body" | grep -q 'soundwire.*master'; then
		append_ev "$off" hardware sdw_master bus "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=sdw fn=state_change'; then
		append_ev "$off" hardware sdw_core state_change "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=sdw fn=completion'; then
		append_ev "$off" kernel sdw_core completion "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=sdw fn=state_skip'; then
		append_ev "$off" kernel sdw_core state_skip "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=amd fn=resume_enter'; then
		append_ev "$off" hardware amd_sdw resume_enter "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=amd fn=ping_status'; then
		append_ev "$off" hardware amd_sdw ping_status "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=amd fn=queue_work'; then
		append_ev "$off" hardware amd_sdw queue_work "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=amd fn=handle_status'; then
		append_ev "$off" kernel amd_sdw handle_status "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=resume_enter'; then
		append_ev "$off" kernel rt721 pm_resume_enter "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=resume_early_exit'; then
		append_ev "$off" kernel rt721 pm_resume_skip "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=branch_fast_path'; then
		append_ev "$off" kernel rt721 pm_branch_fast "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=wait_init_start'; then
		append_ev "$off" kernel rt721 pm_wait_start "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=wait_init_ok'; then
		append_ev "$off" kernel rt721 pm_wait_ok "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=wait_init_timeout'; then
		append_ev "$off" hardware rt721 init_timeout "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=regmap_sync_start'; then
		append_ev "$off" kernel rt721 pm_regmap_sync "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=regmap_sync_done'; then
		append_ev "$off" kernel rt721 pm_regmap_done "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=resume_exit'; then
		append_ev "$off" kernel rt721 pm_resume_exit "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=update_status_attached'; then
		append_ev "$off" hardware rt721 attached "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=pm fn=update_status_unattached'; then
		append_ev "$off" hardware rt721 unattached "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=init fn=io_init_enter'; then
		append_ev "$off" kernel rt721 io_init_enter "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=init fn=io_init_done'; then
		append_ev "$off" kernel rt721 io_init_done "$body"
	elif echo "$body" | grep -q 'PHASE6 ctx=init fn=io_init_skip'; then
		append_ev "$off" kernel rt721 io_init_skip "$body"
	elif echo "$body" | grep -q 'rt721' && echo "$body" | grep -q 'Initialization not complete'; then
		append_ev "$off" hardware rt721 init_timeout "$body"
	elif echo "$body" | grep -q 'rt721' && echo "$body" | grep -q 'failed to resume: error -110'; then
		append_ev "$off" kernel rt721 pm_fail_110 "$body"
	elif echo "$body" | grep -q ':01:8' && echo "$body" | grep -q 'failed to resume: error -110'; then
		append_ev "$off" kernel tas2783_8 pm_fail_110 "$body"
	elif echo "$body" | grep -q ':01:b' && echo "$body" | grep -q 'failed to resume: error -110'; then
		append_ev "$off" kernel tas2783_b pm_fail_110 "$body"
	elif echo "$body" | grep -q 'update_status_attached uid=0x8'; then
		append_ev "$off" hardware tas2783_8 attached "$body"
	elif echo "$body" | grep -q 'update_status_unattached uid=0x8'; then
		append_ev "$off" hardware tas2783_8 unattached "$body"
	elif echo "$body" | grep -q 'update_status_attached uid=0xb'; then
		append_ev "$off" hardware tas2783_b attached "$body"
	elif echo "$body" | grep -q 'update_status_unattached uid=0xb'; then
		append_ev "$off" hardware tas2783_b unattached "$body"
	elif echo "$body" | grep -q 'fn=tas_io_init uid=0x8'; then
		append_ev "$off" kernel tas2783_8 tas_io_init "$body"
	elif echo "$body" | grep -q 'fn=tas2783_fw_ready_done uid=0x8'; then
		append_ev "$off" kernel tas2783_8 fw_ready_done "$body"
	elif echo "$body" | grep -q 'playback without fw' && echo "$body" | grep -q ':01:8'; then
		append_ev "$off" kernel tas2783_8 playback_without_fw "$body"
	elif echo "$body" | grep -q 'hw_params.*SmartAmp\|__soc_pcm_hw_params.*SmartAmp'; then
		append_ev "$off" kernel pcm hw_params "$body"
	elif echo "$body" | grep -qE 'ENZOPLAY.*trigger|snd_pcm_start'; then
		append_ev "$off" kernel pcm trigger "$body"
	else
		return 1
	fi
}

while IFS= read -r line; do
	[[ -z "$line" ]] && continue
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* //')"
	off="$(offset_ms_from_line "$line")"
	classify_kernel_line "$off" "$body" || true
done < <(journalctl -k -b 0 --no-pager --since "$JOURNAL_SINCE" --until "$JOURNAL_UNTIL" 2>/dev/null || true)

while IFS= read -r line; do
	[[ -z "$line" ]] && continue
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* //')"
	off="$(offset_ms_from_line "$line")"
	if echo "$body" | grep -q 'px13-audio-fix:'; then
		append_ev "$off" userspace px13 px13 "$(echo "$body" | sed 's/.*px13-audio-fix: //')"
	elif echo "$body" | grep -qE 'pipewire|wireplumber'; then
		append_ev "$off" userspace pipewire event "$body"
	elif echo "$body" | grep -qE 'systemd-udevd.*sound|alsa.*card'; then
		append_ev "$off" userspace udev sound "$body"
	fi
done < <(journalctl -b 0 --no-pager --since "$JOURNAL_SINCE" --until "$JOURNAL_UNTIL" 2>/dev/null \
	| grep -iE 'px13-audio-fix:|pipewire|wireplumber|systemd-udevd.*sound' || true)

echo "phase6-events-parse: run=${RUN_ID} → ${OUT}"
