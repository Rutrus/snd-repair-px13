#!/usr/bin/env bash
# Deprecated wrapper — use build-from-upstream.sh (full A+B+C) or build-production-modules.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "install-tas2783-ko.sh is deprecated." >&2
echo "Use instead:" >&2
echo "  $SCRIPT_DIR/build-from-upstream.sh        # clean upstream A+B+C (recommended)" >&2
echo "  $SCRIPT_DIR/build-production-modules.sh   # local patches/ with ENZOPLAY" >&2
echo "" >&2
echo "If upstream apply failed, reset the tree first:" >&2
echo "  $SCRIPT_DIR/reset-kernel-tree.sh" >&2
exit 1
