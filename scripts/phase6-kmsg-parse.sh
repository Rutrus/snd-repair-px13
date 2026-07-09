#!/usr/bin/env bash
# Parse kernel chronology since resume → validation/phase6-kmsg-events.csv
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REPO}/validation/phase6-kmsg-events.csv"
RUN_ID="${1:?run_id}"
RESUME_TS="${2:?resume_ts YYYY-MM-DD HH:MM:SS}"

RESUME_EPOCH="$(date -d "$RESUME_TS" +%s 2>/dev/null || date -d "${RESUME_TS/T/ }" +%s)"

if [[ ! -f "$OUT" ]]; then
	echo "run_id,offset_ms,layer,component,event,detail" >"$OUT"
fi

# Resume anchor from kmsg (may differ by 1s from ISO)
ANCHOR="$(journalctl -k -b 0 --no-pager -g 'PM: suspend exit' 2>/dev/null | tail -1)"
ANCHOR_TS="$(echo "$ANCHOR" | awk '{print $1,$2,$3}')"
if [[ -n "$ANCHOR_TS" && "$ANCHOR_TS" != "  " ]]; then
	RESUME_EPOCH="$(date -d "$ANCHOR_TS" +%s 2>/dev/null || echo "$RESUME_EPOCH")"
fi

offset_ms_from_line() {
	local line="$1"
	local ts epoch
	ts="$(echo "$line" | awk '{print $1,$2,$3}')"
	epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
	echo $(( (epoch - RESUME_EPOCH) * 1000 ))
}

classify_line() {
	local off="$1"
	local body="$2"
	local layer="" component="" event="" detail=""
	detail="$(echo "$body" | head -c 200)"

	if echo "$body" | grep -q 'PM: suspend exit'; then
		layer=PM; component=core; event=suspend_exit
	elif echo "$body" | grep -q 'PM: suspend entry'; then
		layer=PM; component=core; event=suspend_entry
	elif echo "$body" | grep -q 'rt721' && echo "$body" | grep -q 'Initialization not complete'; then
		layer=kernel; component=rt721; event=init_timeout
	elif echo "$body" | grep -q 'rt721' && echo "$body" | grep -q 'failed to resume: error -110'; then
		layer=kernel; component=rt721; event=pm_fail_110
	elif echo "$body" | grep -q '0102:0000:01:8' && echo "$body" | grep -q 'failed to resume: error -110'; then
		layer=kernel; component=tas2783_8; event=pm_fail_110
	elif echo "$body" | grep -q '0102:0000:01:b' && echo "$body" | grep -q 'failed to resume: error -110'; then
		layer=kernel; component=tas2783_b; event=pm_fail_110
	elif echo "$body" | grep -q 'update_status_attached uid=0x8'; then
		layer=SDW; component=tas2783_8; event=attached
	elif echo "$body" | grep -q 'update_status_unattached uid=0x8'; then
		layer=SDW; component=tas2783_8; event=unattached
	elif echo "$body" | grep -q 'update_status_attached uid=0xb'; then
		layer=SDW; component=tas2783_b; event=attached
	elif echo "$body" | grep -q 'update_status_unattached uid=0xb'; then
		layer=SDW; component=tas2783_b; event=unattached
	elif echo "$body" | grep -q 'fn=tas_io_init uid=0x8'; then
		layer=kernel; component=tas2783_8; event=tas_io_init
	elif echo "$body" | grep -q 'fn=tas2783_fw_ready_done uid=0x8'; then
		layer=kernel; component=tas2783_8; event=fw_ready_done
	elif echo "$body" | grep -q 'playback without fw' && echo "$body" | grep -q ':01:8'; then
		layer=kernel; component=tas2783_8; event=playback_without_fw
	elif echo "$body" | grep -q 'px13-audio-fix:'; then
		layer=userspace; component=px13; event=px13
		detail="$(echo "$body" | sed 's/.*px13-audio-fix: //' | head -c 200)"
	elif echo "$body" | grep -q 'snd_pci_ps.*IO_PAGE_FAULT'; then
		layer=kernel; component=acp; event=io_page_fault
	else
		return 1
	fi
	printf '%s,%s,%s,%s,%s,%s\n' "$RUN_ID" "$off" "$layer" "$component" "$event" \
		"$(echo "$detail" | tr ',' ';')"
}

JOURNAL_SINCE="$(date -d "@${RESUME_EPOCH}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$RESUME_TS")"

while IFS= read -r line; do
	[[ -z "$line" ]] && continue
	body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* //')"
	off="$(offset_ms_from_line "$line")"
	classify_line "$off" "$body" >>"$OUT" 2>/dev/null || true
done < <(journalctl -k -b 0 --no-pager --since "$JOURNAL_SINCE" 2>/dev/null || true)

echo "phase6-kmsg-parse: run=${RUN_ID} → ${OUT}"
