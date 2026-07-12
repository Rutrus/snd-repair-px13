#!/usr/bin/env bash
# Rescue mode — aggression tree A→I. One question: audio back without reboot?
set -euo pipefail

_RESCUE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../salvage/_lib.sh
source "${_RESCUE_DIR}/../salvage/_lib.sh"

RESCUE_LOG_DIR="${RESCUE_LOG_DIR:-/var/log/snd-repair-rescue}"

rescue_log() { echo "[rescue] $*"; }

rescue_ensure_logdir() {
	mkdir -p "$RESCUE_LOG_DIR" 2>/dev/null || RESCUE_LOG_DIR="${TMPDIR:-/tmp}/snd-repair-rescue"
	mkdir -p "$RESCUE_LOG_DIR"
}

rescue_finish() {
	local lid="$1"
	start_pipewire_all
	bf_strategy_finish "$lid"
}

rescue_rebuild_standard() {
	salvage_rebuild_bottomup
	bf_alsactl_restore
	bf_udev_trigger
}
