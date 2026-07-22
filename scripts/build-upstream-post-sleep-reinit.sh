#!/usr/bin/env bash
# Build 0001 (hw_params second fw_reinit) + 0001b (post-resume dual trigger).
# Stages to build/staging/$KVER — does not write /lib/modules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/modules.sh
source "$SCRIPT_DIR/lib/modules.sh"

C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"

ensure_kernel_tree_writable "$KERNEL_SRC"

grep -Fq resume_playback_reinit_pending "$C_SRC" || \
	python3 "$SCRIPT_DIR/apply-upstream-post-sleep-hw-params.py" "$C_SRC"

grep -Fq 'snd_repair post-resume fw_reinit' "$C_SRC" || \
	python3 "$SCRIPT_DIR/apply-0001b-post-resume-fw-reinit.py" "$C_SRC"

grep -Fq 'tas2783_run_post_resume_fw_reinit_once' "$C_SRC" || {
	echo "ERROR: 0001b run_once missing after apply" >&2
	exit 1
}

KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"

rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.ko \
	"$CODEC_DIR"/.tas2783-sdw.o.cmd "$CODEC_DIR"/.snd-soc-tas2783-sdw.ko.cmd
make -C "$KERNEL_BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules

grep -aFq 'post-sleep playback fw_reinit failed' "$KO" || {
	echo "ERROR: 0001 marker missing in $KO" >&2
	exit 1
}
grep -aFq 'snd_repair post-resume fw_reinit' "$KO" || {
	echo "ERROR: 0001b marker missing in $KO" >&2
	exit 1
}

stage_ko "$KO"

echo "0001+0001b staged. Next:"
echo "  $SCRIPT_DIR/build-amd-soundwire-resume.sh"
echo "  sudo $SCRIPT_DIR/snd-repair install-modules"
echo "Test: Firefox playing → S2 → expect dmesg 'snd_repair post-resume fw_reinit' + sound"
