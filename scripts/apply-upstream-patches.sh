#!/usr/bin/env bash
# Apply clean upstream series (A + B + C) — no debug instrumentation.
#
# Usage:
#   ./scripts/apply-upstream-patches.sh           # apply for real (writes stamp)
#   ./scripts/apply-upstream-patches.sh --check   # dry-run each patch in order, then reset (no stamp)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
STAMP="$SRC/.snd-repair-upstream-applied"
KVER_STAMP="$SRC/.snd-repair-upstream-kernel-version"
PROD_STAMP="$SRC/.snd-repair-production-applied"
KVER="$(uname -r)"
CHECK_ONLY=0
case "${1:-}" in
--check | -n | --dry-run) CHECK_ONLY=1 ;;
"" ) ;;
*)
	echo "Usage: $0 [--check]" >&2
	exit 2
	;;
esac

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

# Dry-run then apply so the next patch in the series sees prior context.
apply_upstream_patch() {
	local patch="$1"
	local label
	label="$(basename "$(dirname "$patch")")/$(basename "$patch")"

	if patch -p1 --forward --dry-run <"$patch" >/tmp/snd-repair-patch-dry.out 2>&1; then
		if [[ "$CHECK_ONLY" -eq 1 ]]; then
			echo "    OK (dry-run) $label"
		fi
		if ! patch -p1 --forward <"$patch" >/dev/null; then
			cleanup_upstream_rejects
			echo "Failed to apply $patch (dry-run OK but apply failed)" >&2
			return 1
		fi
		cleanup_upstream_rejects
		return 0
	fi

	cleanup_upstream_rejects
	if patch_already_applied "$patch"; then
		echo "    already applied — skip $label"
		return 0
	fi
	echo "Failed to apply $patch" >&2
	echo "---- dry-run output ----" >&2
	cat /tmp/snd-repair-patch-dry.out >&2 || true
	echo "Hint: refresh the patch for linux-source matching $KVER (see docs/development-protocol.md §3)." >&2
	return 1
}

if [[ "$CHECK_ONLY" -eq 0 ]]; then
	if [[ -f "$KVER_STAMP" && "$(cat "$KVER_STAMP")" != "$KVER" ]]; then
		echo "==> Kernel changed ($(cat "$KVER_STAMP") → $KVER); clearing apply stamp"
		rm -f "$STAMP"
	fi

	if [[ -f "$STAMP" ]]; then
		echo "Upstream patches already applied ($(cat "$STAMP"))."
		exit 0
	fi
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
	echo "==> CHECK upstream A+B+C on $SRC (kernel $KVER)"
else
	echo "==> Applying upstream series (A + B + C) in $SRC"
fi

fail=0
while IFS= read -r patch; do
	[[ -n "$patch" ]] || continue
	if [[ "$CHECK_ONLY" -eq 0 ]]; then
		echo "    $(basename "$(dirname "$patch")")/$(basename "$patch")"
	fi
	if ! apply_upstream_patch "$patch"; then
		fail=1
		break
	fi
done < <(upstream_patch_files)

if [[ "$fail" -ne 0 ]]; then
	echo "==> FAIL: patch series does not apply cleanly for $KVER" >&2
	exit 1
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
	echo "==> Check OK — resetting tree (no stamp written)"
	"$SCRIPT_DIR/reset-kernel-tree.sh"
	echo "OK: upstream A+B+C apply on source for $KVER"
	exit 0
fi

date -Is >"$STAMP"
echo "$KVER" >"$KVER_STAMP"
echo "==> Done. Build with: $SCRIPT_DIR/build-from-upstream.sh"
