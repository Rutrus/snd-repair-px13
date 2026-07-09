#!/usr/bin/env bash
# Restore patched sound/ files from the distro linux-source tarball and clear stamps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
PKG="linux-source-${KVER%%-*}"
TARBALL=""

if [[ ! -f "$SRC/Makefile" ]]; then
	echo "Missing kernel tree: $SRC — run prepare-kernel-tree.sh first" >&2
	exit 1
fi

if dpkg -l "$PKG" &>/dev/null; then
	TARBALL="$(dpkg -L "$PKG" 2>/dev/null | grep -E '/linux-source-.*\.tar\.(bz2|xz)$' | head -1)"
fi
if [[ -z "$TARBALL" || ! -f "$TARBALL" ]]; then
	echo "Cannot find $PKG tarball (apt install $PKG)" >&2
	exit 1
fi

echo "==> Resetting patched files in $SRC"
echo "    Source tarball: $TARBALL"

cd "$SRC"

rm -f .snd-repair-upstream-applied .snd-repair-upstream-kernel-version \
	.snd-repair-production-applied .snd-repair-kernel-version \
	.snd-repair-production-kernel-version

find sound/soc/codecs sound/soc/sdw_utils -name '*.rej' -o -name '*.orig' 2>/dev/null | while read -r f; do
	rm -f "$f"
done

PREFIX="$(tar -tf "$TARBALL" 2>/dev/null | sed -n '1p' | cut -d/ -f1)"
if [[ -z "$PREFIX" ]]; then
	echo "Cannot read tarball layout: $TARBALL" >&2
	exit 1
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "    Extracting from prefix: $PREFIX"
tar -xf "$TARBALL" -C "$TMP" \
	"$PREFIX/sound/soc/codecs/tas2783-sdw.c" \
	"$PREFIX/sound/soc/sdw_utils"

cp -a "$TMP/$PREFIX/sound/soc/codecs/tas2783-sdw.c" sound/soc/codecs/
cp -a "$TMP/$PREFIX/sound/soc/sdw_utils/." sound/soc/sdw_utils/

if grep -q ENZOPLAY sound/soc/codecs/tas2783-sdw.c 2>/dev/null; then
	echo "Reset failed: ENZOPLAY still present in tas2783-sdw.c" >&2
	exit 1
fi

echo "==> Vanilla sound/soc restored. Apply patches with:"
echo "    $SCRIPT_DIR/apply-upstream-patches.sh   # recommended (A+B+C, no debug)"
echo "    $SCRIPT_DIR/apply-production-patches.sh # local patches/ with ENZOPLAY"
