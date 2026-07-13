#!/usr/bin/env bash
# W4b — phased write trace + W5 manual fw_reinit (requires B + W2 + W4).
#
# Usage:
#   sudo ./scripts/build-w4b-write-trace.sh
#   sudo reboot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

W4_PATCH="$REPO_ROOT/research/make-it-work/patches/w4-tas2783-trace.patch"
W4B_STAMP="$KERNEL_SRC/.snd-repair-w4b-write-trace-applied"
C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"

echo "========================================"
echo " W4b — write trace + W5 manual reinit"
echo "========================================"
echo "kernel_src=$KERNEL_SRC"
echo "(first output is immediate; compile may take 1–2 min)"
echo

ensure_kernel_tree_writable "$KERNEL_SRC"

# W2 only — no full W4 rebuild (build-w4-trace compiles twice; skip it here)
if ! grep -Fq 'W2 ctx=tas fn=force_fw_reinit' "$C_SRC" 2>/dev/null; then
	echo "==> W2 missing — running build-w2-force-fw.sh"
	"$SCRIPT_DIR/build-w2-force-fw.sh" --skip-install
else
	echo "==> W2 present in source"
fi

cd "$KERNEL_SRC"

if ! grep -Fq 'W4 ctx=life seq=' "$C_SRC"; then
	echo "==> W4 missing — applying patch"
	if ! patch -p1 --forward <"$W4_PATCH"; then
		echo "Failed to apply $W4_PATCH" >&2
		exit 1
	fi
else
	echo "==> W4 present in source"
fi

if grep -Fq 'W4b ctx=write' "$C_SRC"; then
	echo "==> W4b already in source — repairing order if needed"
	python3 "$SCRIPT_DIR/repair-w4b-source-order.py" "$C_SRC"
else
	echo "==> Applying W4b write trace + W5 debugfs"
	python3 "$SCRIPT_DIR/apply-w4b-write-trace.py" "$C_SRC"
	date -Is >"$W4B_STAMP"
fi

grep -Fq 'W4b ctx=write' "$C_SRC" || { echo "W4b missing" >&2; exit 1; }
grep -Fq 'tas2783_w5_reinit_write' "$C_SRC" || { echo "W5 missing" >&2; exit 1; }

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
name="snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"

[[ -d "$BUILD" ]] || { echo "Missing headers: linux-headers-$KVER" >&2; exit 1; }

echo "==> Rebuilding snd-soc-tas2783-sdw (B + W2 + W4 + W4b + W5)"
rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.o \
	"$CODEC_DIR"/snd-soc-tas2783-sdw.ko "$CODEC_DIR"/.tas2783-sdw.o.cmd \
	"$CODEC_DIR"/.snd-soc-tas2783-sdw.ko.cmd
make -C "$BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules

[[ -f "$KO" ]] || { echo "Missing $KO" >&2; exit 1; }
grep -aFq 'W4b ctx=write' "$KO" || { echo "W4b not in module" >&2; exit 1; }
echo "OK: W4b present in module"

echo "==> Compressing and installing $dest"
zstd -f "$KO" -o "/tmp/$name.zst"
if [[ $EUID -eq 0 ]]; then
	cp "/tmp/$name.zst" "$dest"
	depmod -a
else
	sudo cp "/tmp/$name.zst" "$dest"
	sudo depmod -a
fi

cat <<EOF

==> W4b + W5 installed. Reboot, then:

1. Cold PASS:
   speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
   sudo ./scripts/w4b-write-trace-capture.sh --label pass --window playback

2. S2 FAIL:
   systemctl suspend && sleep 20
   speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
   sudo ./scripts/w4b-write-trace-capture.sh --label fail-s2 --window playback

3. Write diff:
   ./scripts/w4-write-trace-diff.sh validation/w4b-write-pass-* validation/w4b-write-fail-s2-*

4. W5 double fw_reinit:
   sudo ./scripts/w5-double-fw-reinit-test.sh

Docs: research/experiments/w4b-write-trace-protocol.md
EOF
