#!/usr/bin/env bash
# Build and stage modules from clean upstream/ patches (recommended for end users).
# Does not write to /lib/modules — run: sudo ./scripts/snd-repair install-modules
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/modules.sh
source "$SCRIPT_DIR/lib/modules.sh"

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

stage_ko sound/soc/codecs/snd-soc-tas2783-sdw.ko
stage_ko sound/soc/sdw_utils/snd-soc-sdw-utils.ko

echo ""
echo "==> Staged (upstream base) for kernel $KVER"
echo "    Note: run build-upstream-post-sleep-reinit.sh for patch 0001 before install-modules"
echo "Next:"
echo "  $SCRIPT_DIR/build-upstream-post-sleep-reinit.sh"
echo "  $SCRIPT_DIR/build-amd-soundwire-resume.sh"
echo "  sudo $SCRIPT_DIR/snd-repair install-modules"
