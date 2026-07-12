#!/usr/bin/env bash
# ST01 — SALVAGE-TOPOLOGY: discover live tree (read-only).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SID="ST01"
salvage_log "step ${SID}: discover topology"
"${SCRIPT_DIR}/discover-topology.sh"
salvage_action_ok "topology" "see ${SALVAGE_LOG_DIR}/topology-*.txt"
echo "RESULT=ACTION_OK STRATEGY=${SID} TIME=$(bf_timestamp)"
