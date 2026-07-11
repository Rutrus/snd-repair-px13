#!/usr/bin/env bash
# Restore Phase 6 AMD trace sources from distro tarball (vanilla).
# Used when switching Phase 7 experiments so phase6 patches re-apply cleanly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
PKG="linux-source-${KVER%%-*}"
TARBALL=""

if [[ ! -f "$SRC/Makefile" ]]; then
	echo "Missing kernel tree: $SRC" >&2
	exit 1
fi

if dpkg -l "$PKG" &>/dev/null; then
	TARBALL="$(dpkg -L "$PKG" 2>/dev/null | grep -E '/linux-source-.*\.tar\.(bz2|xz)$' | head -1)"
fi
if [[ -z "$TARBALL" || ! -f "$TARBALL" ]]; then
	echo "Cannot find $PKG tarball (apt install $PKG)" >&2
	exit 1
fi

PREFIX="$(tar -tf "$TARBALL" 2>/dev/null | sed -n '1p' | cut -d/ -f1)"
[[ -n "$PREFIX" ]] || { echo "Cannot read tarball layout: $TARBALL" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

tar -xf "$TARBALL" -C "$TMP" \
	"$PREFIX/drivers/soundwire/amd_manager.c" \
	"$PREFIX/sound/soc/amd/ps/pci-ps.c"

cp -a "$TMP/$PREFIX/drivers/soundwire/amd_manager.c" "$SRC/drivers/soundwire/amd_manager.c"
cp -a "$TMP/$PREFIX/sound/soc/amd/ps/pci-ps.c" "$SRC/sound/soc/amd/ps/pci-ps.c"
rm -f "$SRC/drivers/soundwire/amd_manager.c.orig" "$SRC/drivers/soundwire/amd_manager.c.rej" \
	"$SRC/sound/soc/amd/ps/pci-ps.c.rej"

if grep -qE 'PHASE6|phase7_delay_ms|fn=intr_decode' "$SRC/drivers/soundwire/amd_manager.c"; then
	echo "Reset failed: trace markers still present in amd_manager.c" >&2
	exit 1
fi
if grep -qE 'PHASE6|fn=irq_handler_enter' "$SRC/sound/soc/amd/ps/pci-ps.c"; then
	echo "Reset failed: trace markers still present in pci-ps.c" >&2
	exit 1
fi

echo "==> Vanilla amd_manager.c + pci-ps.c restored from $TARBALL"
