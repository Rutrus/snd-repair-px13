#!/usr/bin/env bash
# Build/install from local patches/ (includes ENZOPLAY in 0009). Prefer build-from-upstream.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"

if [[ ! -f "$SRC/.snd-repair-production-applied" ]]; then
	"$SCRIPT_DIR/apply-production-patches.sh"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Faltan headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

cd "$SRC"

echo "==> Compilando snd-soc-tas2783-sdw"
make -C "$BUILD" M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules

echo "==> Compilando snd-soc-sdw-utils"
make -C "$BUILD" M="$(pwd)/sound/soc/sdw_utils" CONFIG_SND_SOC_SDW_UTILS=m modules

install_ko() {
	local ko="$1"
	local dest_subpath="$2"
	local name
	name="$(basename "$ko")"
	local dest="/lib/modules/$KVER/kernel/$dest_subpath/${name}.zst"
	local backup="$HOME/${name}.zst.orig"

	if [[ ! -f "$ko" ]]; then
		echo "No existe $ko" >&2
		exit 1
	fi

	if [[ ! -f "$backup" && -f "$dest" ]]; then
		echo "==> Backup: $backup"
		sudo cp "$dest" "$backup"
	fi

	zstd -19 -f "$ko" -o "/tmp/$name.zst"
	echo "==> Instalando $dest"
	sudo cp "/tmp/$name.zst" "$dest"
}

install_ko sound/soc/codecs/snd-soc-tas2783-sdw.ko sound/soc/codecs
install_ko sound/soc/sdw_utils/snd-soc-sdw-utils.ko sound/soc/sdw_utils

sudo depmod -a

echo ""
echo "==> Instalado para kernel $KVER"
modinfo snd_soc_tas2783_sdw 2>/dev/null | grep vermagic || true
echo "Reinicia: sudo reboot"
