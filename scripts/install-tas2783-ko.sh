#!/bin/bash
# Compila e instala snd-soc-tas2783-sdw (parches 0004+0006+0007; sin 0009/sdw-utils).
# Para solución completa usar build-production-modules.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
DEST="/lib/modules/$KVER/kernel/sound/soc/codecs"

cd "$SRC"
make -C "$KERNEL_BUILD" \
	M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules

if [[ ! -f sound/soc/codecs/snd-soc-tas2783-sdw.ko ]]; then
	echo "Build failed" >&2
	exit 1
fi

if [[ ! -f ~/snd-soc-tas2783-sdw.ko.zst.orig ]]; then
	sudo cp "$DEST/snd-soc-tas2783-sdw.ko.zst" ~/snd-soc-tas2783-sdw.ko.zst.orig
fi

zstd -19 -f sound/soc/codecs/snd-soc-tas2783-sdw.ko -o /tmp/snd-soc-tas2783-sdw.ko.zst
sudo cp /tmp/snd-soc-tas2783-sdw.ko.zst "$DEST/"
sudo depmod -a

zstdcat /tmp/snd-soc-tas2783-sdw.ko.zst | strings | grep -E 'TAS2783_FW_NWRITE|wait timeout in hw_params' || true

echo "Instalado (solo tas2783). Para estéreo completo: $SCRIPT_DIR/build-production-modules.sh"
