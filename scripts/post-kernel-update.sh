#!/usr/bin/env bash
# Tras apt upgrade: recompila módulos si el kernel cambió o faltan parches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

KVER="$(uname -r)"
MARKER="/lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst"
STAMP="$KERNEL_SRC/.snd-repair-upstream-applied"

needs_build() {
	[[ ! -f "$MARKER" ]] && return 0
	[[ ! -f "$STAMP" ]] && return 0
	# Módulo instalado pero árbol no coincide con este kernel
	if ! modinfo snd_soc_tas2783_sdw 2>/dev/null | grep -q "vermagic:.*$KVER"; then
		return 0
	fi
	return 1
}

if needs_build; then
	echo "snd_repair: reconstruyendo módulos para $KVER"
	rm -f "$STAMP"
	"$SCRIPT_DIR/prepare-kernel-tree.sh"
	"$SCRIPT_DIR/build-from-upstream.sh"
else
	echo "snd_repair: módulos OK para $KVER"
fi
