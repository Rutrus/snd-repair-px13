#!/usr/bin/env bash
# V005 — Who holds soundwire/snd modules open? (refcnt + fuser)
set -euo pipefail
VALIDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BF_DIR="$(cd "${VALIDATE_DIR}/.." && pwd)"
# shellcheck source=../_lib.sh
source "${BF_DIR}/_lib.sh"
# shellcheck source=../../salvage/_lib.sh
source "${BF_DIR}/../salvage/_lib.sh"
require_root "$0"
bf_log "V005: module holders"
salvage_module_holders_report
bf_log "V005: anchor remove plan (dry-run)"
bf_modprobe_remove_plan "$BF_ANCHOR_MOD" 2>&1 | sed 's/^/[bruteforce]   /' || true
bf_log "V005 done"
