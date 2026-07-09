#!/usr/bin/env bash
# Snapshot de investigación multi-track — PX13
# Uso: ~/snd_repair/scripts/investigation-snapshot.sh [etiqueta]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-$(date +%Y%m%d-%H%M%S)}"
OUT="${REPO}/research/snapshots/${TAG}"
mkdir -p "$OUT"

log() { echo "snapshot: $*"; }

log "→ $OUT"

{
	echo "# investigation snapshot tag=${TAG}"
	echo "# timestamp=$(date -Is)"
	echo "# kernel=$(uname -r)"
	echo "# boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
	echo
	echo "## wpctl audio/video"
	wpctl status 2>/dev/null | grep -E 'Speaker|Dummy|webcam|Coprocessor' || true
	echo
	echo "## groups $(whoami)"
	groups 2>/dev/null || true
	echo
	echo "## /dev/media0 video render"
	ls -la /dev/media0 /dev/video0 /dev/dri/renderD128 2>/dev/null || true
	getfacl /dev/media0 2>/dev/null | head -8 || true
	echo
	echo "## asound cards"
	cat /proc/asound/cards 2>/dev/null || true
	echo
	echo "## kernel FW (last 15)"
	journalctl -k -b --no-pager 2>/dev/null \
		| grep -iE 'playback without fw|failed to resume|FW download failed|trf on Slave.*-110' \
		| tail -15 || true
	echo
	echo "## wireplumber media (last 10)"
	journalctl -b --no-pager 2>/dev/null \
		| grep -iE 'media0|dma-buf|libcamera.*ERROR' | tail -10 || true
	echo
	echo "## px13-audio-fix (last 10)"
	journalctl -b --no-pager 2>/dev/null | grep -i px13-audio-fix | tail -10 || true
	echo
	echo "## fw-matrix last row"
	tail -1 "${REPO}/validation/fw-matrix.csv" 2>/dev/null || true
} >"${OUT}/snapshot.txt"

journalctl -k -b --no-pager 2>/dev/null \
	| grep -iE 'tas2783|FW download|playback without fw|SDW1-PIN4|failed to resume' \
	>"${OUT}/kernel-filtered.log" || true

log "written ${OUT}/snapshot.txt"
log "written ${OUT}/kernel-filtered.log"
