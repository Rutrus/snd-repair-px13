#!/usr/bin/env bash
# V003 — Kernel objects snapshot (baseline).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
bf_log "V003: kernel objects baseline"
bf_kernel_objects_snapshot "baseline"
bf_log "V003 done"
