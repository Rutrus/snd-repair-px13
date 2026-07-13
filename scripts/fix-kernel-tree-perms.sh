#!/usr/bin/env bash
# Restore write access to kernel source build dirs after sudo builds.
#
# Usage:
#   ./scripts/fix-kernel-tree-perms.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ensure_kernel_tree_writable "$KERNEL_SRC"
echo "==> Done. Re-run your build script (without sudo unless installing .ko)."
