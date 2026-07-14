#!/usr/bin/env bash
# W7 — post-S2 millisecond timeline (W2/W5/W6/playback milestones).
#
# Usage:
#   sudo ./scripts/build-w7-ts-trace.sh
#   sudo reboot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"

echo "========================================"
echo " W7 — post-S2 timestamp trace"
echo "========================================"

ensure_kernel_tree_writable "$KERNEL_SRC"

if ! grep -Fq 'W6 ctx=deferred fn=fw_reinit' "$C_SRC" 2>/dev/null; then
	echo "==> W6 missing — run build-w6-deferred-reinit.sh first" >&2
	exit 1
fi

if grep -Fq 'W7 ctx=ts uid=' "$C_SRC"; then
	echo "==> W7 already in source"
else
	python3 "$SCRIPT_DIR/apply-w7-ts-trace.py" "$C_SRC"
fi

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst"

[[ -d "$BUILD" ]] || { echo "Missing headers: linux-headers-$KVER" >&2; exit 1; }

echo "==> Rebuilding snd-soc-tas2783-sdw (+ W7)"
rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.ko
make -C "$BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules
grep -aFq 'W7 ctx=ts uid=' "$KO" || { echo "W7 not in module" >&2; exit 1; }

zstd -f "$KO" -o "/tmp/snd-soc-tas2783-sdw.ko.zst"
if [[ $EUID -eq 0 ]]; then
	cp "/tmp/snd-soc-tas2783-sdw.ko.zst" "$dest"
	depmod -a
else
	sudo cp "/tmp/snd-soc-tas2783-sdw.ko.zst" "$dest"
	sudo depmod -a
fi

cat <<'EOF'

==> W7 installed. Reboot, then capture timeline after S2:

  sudo ./scripts/w7-ts-capture.sh --last-s2
  journalctl -k -b 0 | grep 'W7 ctx=ts'

Docs: research/experiments/w5-reproducibility-protocol.md
EOF
