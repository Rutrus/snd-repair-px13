#!/usr/bin/env bash
# V001 — Module inventory: what exists, what's loaded, what modprobe -r -v plans.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../_lib.sh
source "$SCRIPT_DIR/_lib.sh"
require_root "$0"
bf_log "V001: module inventory"
bf_inventory_modules
bf_log "V001 done"
