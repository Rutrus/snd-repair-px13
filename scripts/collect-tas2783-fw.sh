#!/bin/bash
# Recoge estado FW TAS2783 tras cada boot → matriz para caracterizar -110
# Uso: ./collect-tas2783-fw.sh [archivo.log]

set -euo pipefail

LOG="${1:-${HOME}/tas2783-fw-matrix.log}"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id)"
DATE="$(date -Is)"
UPTIME="$(cut -d. -f1 /proc/uptime)"

if command -v journalctl >/dev/null 2>&1; then
	KMLOG="$(journalctl -k -b 0 --no-pager 2>/dev/null || true)"
else
	KMLOG="$(dmesg 2>/dev/null || true)"
fi

uid_status() {
	local uid="$1"
	local fail pb

	fail="$(printf '%s\n' "$KMLOG" | grep -c "0102:0000:01:${uid}.*FW download failed" || true)"
	pb="$(printf '%s\n' "$KMLOG" | grep -c "0102:0000:01:${uid}.*playback without fw" || true)"

	if [[ "$fail" -gt 0 ]]; then
		echo "FAIL(fw)"
	elif [[ "$pb" -gt 0 ]]; then
		echo "WARN(no-fw-hw_params)"
	else
		echo "OK"
	fi
}

S8="$(uid_status 8)"
SB="$(uid_status b)"

{
	echo "===== ${DATE} boot_id=${BOOT_ID} uptime=${UPTIME}s ====="
	echo "  :8 (tas2783-1 Left)  = ${S8}"
	echo "  :b (tas2783-2 Right) = ${SB}"
	printf '%s\n' "$KMLOG" | grep -E \
		'ENZOFW\[|FW download failed|fw with no files|playback without fw|Failed to read fw binary' |
		grep -E '0102:0000:01:(8|b)|ENZOFW' | sed 's/^/  /' || true
	echo ""
} | tee -a "$LOG"

echo "→ ${LOG}"
