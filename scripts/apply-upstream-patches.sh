#!/usr/bin/env bash
# Apply clean upstream series (A + B + C) — no debug instrumentation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
STAMP="$SRC/.snd-repair-upstream-applied"
KVER_STAMP="$SRC/.snd-repair-upstream-kernel-version"
PROD_STAMP="$SRC/.snd-repair-production-applied"
KVER="$(uname -r)"

if [[ ! -f "$SRC/Makefile" ]]; then
	echo "Run first: $SCRIPT_DIR/prepare-kernel-tree.sh" >&2
	exit 1
fi

if [[ -f "$PROD_STAMP" ]]; then
	echo "Local production patches (patches/) were applied on this tree." >&2
	echo "Reset first: $SCRIPT_DIR/reset-kernel-tree.sh" >&2
	exit 1
fi

if grep -q ENZOPLAY "$SRC/sound/soc/codecs/tas2783-sdw.c" 2>/dev/null; then
	echo "Tree has production/debug changes (ENZOPLAY) without a clean reset." >&2
	echo "Run: $SCRIPT_DIR/reset-kernel-tree.sh" >&2
	exit 1
fi

cd "$SRC"

cleanup_upstream_rejects() {
	find . -name '*.rej' -delete 2>/dev/null || true
}

patch_already_applied() {
	local patch="$1"
	patch -p1 --reverse --dry-run <"$patch" >/dev/null 2>&1
}

apply_upstream_patch() {
	local patch="$1"
	if patch -p1 --forward <"$patch"; then
		cleanup_upstream_rejects
		return 0
	fi
	cleanup_upstream_rejects
	if patch_already_applied "$patch"; then
		echo "    already applied — skip"
		return 0
	fi
	echo "Failed to apply $patch" >&2
	return 1
}

if [[ -f "$KVER_STAMP" && "$(cat "$KVER_STAMP")" != "$KVER" ]]; then
	echo "==> Kernel changed ($(cat "$KVER_STAMP") → $KVER); resetting patched tree"
	rm -f "$STAMP"
fi

if [[ -f "$STAMP" ]]; then
	echo "Upstream patches already applied ($(cat "$STAMP"))."
	exit 0
fi

echo "==> Applying upstream series (A + B + C) in $SRC"
while IFS= read -r patch; do
	[[ -n "$patch" ]] || continue
	echo "    $(basename "$(dirname "$patch")")/$(basename "$patch")"
	apply_upstream_patch "$patch" || exit 1
done < <(upstream_patch_files)

date -Is >"$STAMP"
echo "$KVER" >"$KVER_STAMP"
echo "==> Done. Build with: $SCRIPT_DIR/build-from-upstream.sh"
