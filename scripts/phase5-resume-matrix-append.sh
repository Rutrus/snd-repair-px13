#!/usr/bin/env bash
# Append one composite row to validation/resume-matrix.csv from a bifurcation run.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MATRIX="${REPO}/validation/resume-matrix.csv"
RUN_ID=""
BOOT_ID=""
RESUME_TS=""
TIMELINE=""
NOTES=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--run-id) RUN_ID="$2"; shift 2 ;;
	--boot-id) BOOT_ID="$2"; shift 2 ;;
	--resume-ts) RESUME_TS="$2"; shift 2 ;;
	--timeline) TIMELINE="$2"; shift 2 ;;
	--notes) NOTES="$2"; shift 2 ;;
	*) shift ;;
	esac
done

[[ -n "$RUN_ID" && -f "$TIMELINE" ]] || exit 0

if [[ ! -f "$MATRIX" ]]; then
	echo "boot_id,run_id,resume_ts,pm,attach,fw,speaker,audio,composite,uid8_attach_t60,post_pci_attach,notes" >"$MATRIX"
fi

# Use t=60s row if present, else last row of this run
ROW="$(awk -F, -v rid="$RUN_ID" '
	$1 == rid && $5 == 60 { print; found=1 }
	END { if (!found) exit 1 }
' "$TIMELINE" 2>/dev/null)" || \
ROW="$(awk -F, -v rid="$RUN_ID" '$1 == rid { last=$0 } END { print last }' "$TIMELINE")"

[[ -n "$ROW" ]] || exit 0

IFS=',' read -r _rid _boot _pb _rts _off pm a8 _ab _a721 fw8 _fwb pw sink sp pb _rt8 _rtb _rt721 audio composite _notes <<<"$ROW"

# post_pci_attach: any attached after px13 PCI bind in kmsg since resume
post_pci="UNK"
if command -v journalctl >/dev/null 2>&1; then
	resume_journal="$(date -d "${RESUME_TS}" '+%b %d %H:%M:%S' 2>/dev/null || true)"
	if journalctl -k -b 0 --no-pager --since "$resume_journal" 2>/dev/null \
		| grep -q 'px13-audio-fix: binding PCI'; then
		if journalctl -k -b 0 --no-pager --since "$resume_journal" 2>/dev/null \
			| grep -q 'update_status_attached uid=0x8'; then
			post_pci="YES"
		else
			post_pci="NO"
		fi
	else
		post_pci="N/A"
	fi
fi

attach_ok="NO"
[[ "$a8" == "YES" ]] && attach_ok="YES"
fw_ok="NO"
[[ "$fw8" == "YES" ]] && fw_ok="YES"
pm_ok="OK"
[[ "$pm" == "FAIL" ]] && pm_ok="FAIL"

{
	printf '%s,' "$BOOT_ID"
	printf '%s,' "$RUN_ID"
	printf '%s,' "$RESUME_TS"
	printf '%s,' "$pm_ok"
	printf '%s,' "$attach_ok"
	printf '%s,' "$fw_ok"
	printf '%s,' "$sp"
	printf '%s,' "$audio"
	printf '%s,' "$composite"
	printf '%s,' "$a8"
	printf '%s,' "$post_pci"
	printf '%s\n' "${NOTES:-}"
} >>"$MATRIX"

echo "resume-matrix: appended run=${RUN_ID} composite=${composite}"
