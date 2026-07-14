#!/usr/bin/env bash
# Build upstream candidate: one-shot fw_reinit on first hw_params after system sleep.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"

ensure_kernel_tree_writable "$KERNEL_SRC"

grep -Fq resume_playback_reinit_pending "$C_SRC" || \
	python3 "$SCRIPT_DIR/apply-upstream-post-sleep-hw-params.py" "$C_SRC"

KVER="$(uname -r)"
KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst"

rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.ko
make -C "$KERNEL_BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules
grep -aFq 'post-sleep playback fw_reinit failed' "$KO"

zstd -f "$KO" -o "/tmp/snd-soc-tas2783-sdw.ko.zst"
[[ $EUID -eq 0 ]] && cp "/tmp/snd-soc-tas2783-sdw.ko.zst" "$dest" && depmod -a || \
	sudo cp "/tmp/snd-soc-tas2783-sdw.ko.zst" "$dest" && sudo depmod -a

echo "Upstream candidate installed. Test: S2 → speaker-test hw:1,2 (mask PW if EBUSY)"
