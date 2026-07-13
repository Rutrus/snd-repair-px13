#!/usr/bin/env bash
# W6 — configurable deferred second fw_reinit after W2 (timing sweep experiment).
#
# Usage:
#   sudo ./scripts/build-w6-deferred-reinit.sh
#   sudo reboot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"
W6_STAMP="$KERNEL_SRC/.snd-repair-w6-deferred-reinit-applied"

echo "========================================"
echo " W6 — deferred second fw_reinit"
echo "========================================"
echo "kernel_src=$KERNEL_SRC"
echo

ensure_kernel_tree_writable "$KERNEL_SRC"

if ! grep -Fq 'W4b ctx=write' "$C_SRC" 2>/dev/null; then
	echo "==> W4b/W5 missing — run build-w4b-write-trace.sh first" >&2
	exit 1
fi

if grep -Fq 'W6 ctx=deferred fn=fw_reinit' "$C_SRC"; then
	echo "==> W6 already in source"
else
	echo "==> Applying W6 deferred reinit experiment"
	python3 "$SCRIPT_DIR/apply-w6-deferred-reinit.py" "$C_SRC"
	date -Is >"$W6_STAMP"
fi

grep -Fq 'deferred_reinit_ms' "$C_SRC" || { echo "W6 missing" >&2; exit 1; }

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
name="snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"

[[ -d "$BUILD" ]] || { echo "Missing headers: linux-headers-$KVER" >&2; exit 1; }

echo "==> Rebuilding snd-soc-tas2783-sdw (B + W2 + W4 + W4b + W5 + W6)"
rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.o \
	"$CODEC_DIR"/snd-soc-tas2783-sdw.ko "$CODEC_DIR"/.tas2783-sdw.o.cmd \
	"$CODEC_DIR"/.snd-soc-tas2783-sdw.ko.cmd
make -C "$BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules

[[ -f "$KO" ]] || { echo "Missing $KO" >&2; exit 1; }
grep -aFq 'W6 ctx=deferred fn=fw_reinit' "$KO" || { echo "W6 not in module" >&2; exit 1; }
echo "OK: W6 present in module"

echo "==> Compressing and installing $dest"
zstd -f "$KO" -o "/tmp/$name.zst"
if [[ $EUID -eq 0 ]]; then
	cp "/tmp/$name.zst" "$dest"
	depmod -a
else
	sudo cp "/tmp/$name.zst" "$dest"
	sudo depmod -a
fi

cat <<'EOF'

==> W6 installed. Reboot, then sweep delays:

  sudo ./scripts/w6-deferred-reinit-sweep.sh --delay 0
  sudo ./scripts/w6-deferred-reinit-sweep.sh --delay 500
  sudo ./scripts/w6-deferred-reinit-sweep.sh --delay 1000
  ...

Or event-driven (first port PRE_PREP after W2):
  echo 1 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/deferred_reinit_on_port_prep
  echo 0 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/deferred_reinit_ms

Docs: research/experiments/w6-deferred-reinit-protocol.md
EOF
