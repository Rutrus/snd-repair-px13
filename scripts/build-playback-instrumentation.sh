#!/bin/bash
# Compila snd-soc-tas2783-sdw + snd-soc-sdw-utils (0004–0008, depuración ENZOPLAY)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"

cd "$SRC"

make -C "$BUILD" M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules
make -C "$BUILD" M="$(pwd)/sound/soc/sdw_utils" CONFIG_SND_SOC_SDW_UTILS=m modules

for ko in sound/soc/codecs/snd-soc-tas2783-sdw.ko sound/soc/sdw_utils/snd-soc-sdw-utils.ko; do
	[[ -f "$ko" ]] || { echo "Falta $ko" >&2; exit 1; }
	zstd -19 -f "$ko" -o "/tmp/$(basename "$ko").zst"
	zstdcat "/tmp/$(basename "$ko").zst" | strings | grep -q ENZOPLAY && echo "OK ENZOPLAY en $(basename "$ko")"
done

cat <<EOF

Instalación (sudo):
  KVER=\$(uname -r)
  sudo cp /tmp/snd-soc-tas2783-sdw.ko.zst \\
    /lib/modules/\$KVER/kernel/sound/soc/codecs/
  sudo cp /tmp/snd-soc-sdw-utils.ko.zst \\
    /lib/modules/\$KVER/kernel/sound/soc/sdw_utils/
  sudo depmod -a && sudo reboot

Tras reboot:
  $SCRIPT_DIR/run-stereo-phase1.sh
  grep ENZOPLAY ~/tas2783-stereo-phase1.log
EOF
