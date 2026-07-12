#!/usr/bin/env bash
# SD40 — Full top-down teardown + bottom-up rebuild (verify each level).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="SD40"
salvage_log "step ${SID}: top-down teardown + rebuild"
"${SCRIPT_DIR}/discover-topology.sh" --emit "${SALVAGE_LOG_DIR}/SD40-topology-before.txt"
bf_kernel_objects_snapshot "SD40-before"

cleared="$(salvage_teardown_topdown)"
salvage_log "levels fully cleared: ${cleared}/3 (pci+sof+soundwire)"

salvage_rebuild_bottomup
bf_alsactl_restore
bf_udev_trigger
start_pipewire_all
bf_kernel_objects_snapshot "SD40-after"
bf_strategy_finish "$SID"
