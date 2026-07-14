#!/usr/bin/env bash
# W8 — context-triggered 2nd fw_reinit (hw_params / port_prep / dapm POST_PMU).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"

ensure_kernel_tree_writable "$KERNEL_SRC"

for need in W7 ctx=ts W6 ctx=deferred; do
	grep -Fq "$need" "$C_SRC" || {
		echo "Missing $need — run build-w7-ts-trace.sh first" >&2
		exit 1
	}
done

grep -Fq deferred_reinit_on_hw_params "$C_SRC" || \
	python3 "$SCRIPT_DIR/apply-w8-context-reinit.py" "$C_SRC"

KVER="$(uname -r)"
KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst"

rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.ko
make -C "$KERNEL_BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules
grep -aFq 'W8 ctx=%s fn=fw_reinit uid=%d' "$KO"

zstd -f "$KO" -o "/tmp/snd-soc-tas2783-sdw.ko.zst"
[[ $EUID -eq 0 ]] && cp "/tmp/snd-soc-tas2783-sdw.ko.zst" "$dest" && depmod -a || \
	sudo cp "/tmp/snd-soc-tas2783-sdw.ko.zst" "$dest" && sudo depmod -a

echo "W8 installed. Reboot, then: sudo ./scripts/w8-context-reinit-test.sh --mode hw-params"
