#!/usr/bin/env bash
# Build and install modules from clean upstream/ patches (recommended for end users).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"

if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	if find "$SRC/sound/soc" -name '*.rej' 2>/dev/null | grep -q .; then
		echo "Stale .rej files — reset first: $SCRIPT_DIR/reset-kernel-tree.sh" >&2
		exit 1
	fi
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

cd "$SRC"
ensure_kernel_tree_writable "$SRC"

echo "==> Building snd-soc-tas2783-sdw (upstream series)"
make -C "$BUILD" M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules

echo "==> Building snd-soc-sdw-utils (upstream series)"
make -C "$BUILD" M="$(pwd)/sound/soc/sdw_utils" CONFIG_SND_SOC_SDW_UTILS=m modules

install_ko() {
	local ko="$1"
	local dest_subpath="$2"
	local name
	name="$(basename "$ko")"
	local dest="/lib/modules/$KVER/kernel/$dest_subpath/${name}.zst"
	local backup="$HOME/${name}.zst.orig"

	[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

	if [[ ! -f "$backup" && -f "$dest" ]]; then
		echo "==> Backup: $backup"
		sudo cp "$dest" "$backup"
	fi

	zstd -19 -f "$ko" -o "/tmp/$name.zst"
	echo "==> Installing $dest"
	sudo cp "/tmp/$name.zst" "$dest"
}

install_ko sound/soc/codecs/snd-soc-tas2783-sdw.ko sound/soc/codecs
install_ko sound/soc/sdw_utils/snd-soc-sdw-utils.ko sound/soc/sdw_utils

sudo depmod -a

echo ""
echo "==> Installed (upstream, no debug traces) for kernel $KVER"
modinfo snd_soc_tas2783_sdw 2>/dev/null | grep vermagic || true
echo "Reboot: sudo reboot"
