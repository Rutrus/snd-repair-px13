#!/usr/bin/env bash
# Deprecated — use scripts/recovery/run-recovery.sh R04
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/recovery/run-recovery.sh" "${@:-}"
