#!/usr/bin/env bash
# W4 — TAS2783 lifecycle + SDCA trace on snd-soc-tas2783-sdw (requires B + W2).
#
# Usage:
#   sudo ./scripts/build-w4-trace.sh
#   sudo ./scripts/build-w4-trace.sh --sdca-trace   # enable w4_sdca_trace at load
#   sudo reboot
#
# Cold boot PASS — capture lifecycle:
#   sudo ./scripts/w4-trace-capture.sh --label pass-cold
#   speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
#   sudo ./scripts/w4-trace-capture.sh --label pass-cold-playback
#
# Post-S2 FAIL — same:
#   systemctl suspend && sleep 20
#   speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
#   sudo ./scripts/w4-trace-capture.sh --label fail-s2-playback
#
# Diff ordered lifecycle (first divergence wins):
#   ./scripts/w4-trace-diff.sh validation/w4-trace-pass-cold-playback-* \
#                               validation/w4-trace-fail-s2-playback-*
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

W4_PATCH="$REPO_ROOT/research/make-it-work/patches/w4-tas2783-trace.patch"
W4_STAMP="$KERNEL_SRC/.snd-repair-w4-trace-applied"
ENABLE_SDCA_TRACE=0

W2_ARGS=(--skip-install)
while [[ $# -gt 0 ]]; do
	case "$1" in
	--sdca-trace) ENABLE_SDCA_TRACE=1; shift ;;
	--trace) W2_ARGS+=(--trace) ;;
	--skip-install) ;;
	-h|--help)
		sed -n '3,22p' "$0"
		exit 0
		;;
	*) W2_ARGS+=("$1"); shift ;;
	esac
done

"$SCRIPT_DIR/build-w2-force-fw.sh" "${W2_ARGS[@]}"

cd "$KERNEL_SRC"
C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"

if grep -Fq 'W4 ctx=life seq=' "$C_SRC"; then
	echo "==> W4 trace already in source — skipping patch"
	date -Is >"$W4_STAMP"
elif patch -p1 --forward <"$W4_PATCH"; then
	date -Is >"$W4_STAMP"
else
	echo "Failed to apply $W4_PATCH" >&2
	exit 1
fi

grep -Fq 'W4 ctx=life seq=' "$C_SRC" || { echo "W4 not in source" >&2; exit 1; }

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"
KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
name="snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"

echo "==> Rebuilding snd-soc-tas2783-sdw (B + W2 + W4)"
rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.o \
	"$CODEC_DIR"/snd-soc-tas2783-sdw.ko "$CODEC_DIR"/.tas2783-sdw.o.cmd \
	"$CODEC_DIR"/.snd-soc-tas2783-sdw.ko.cmd
make -C "$BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules

[[ -f "$KO" ]] || { echo "Missing $KO" >&2; exit 1; }

if ! grep -aFq 'W4 ctx=life seq=' "$KO" 2>/dev/null; then
	echo "ERROR: W4 not present in $KO" >&2
	exit 1
fi
echo "OK: W4 present in source + module"

zstd -19 -f "$KO" -o "/tmp/$name.zst"
echo "==> Installing $dest"
sudo cp "/tmp/$name.zst" "$dest"
sudo depmod -a

MODCONF="/etc/modprobe.d/snd-repair-w4-trace.conf"
if [[ "$ENABLE_SDCA_TRACE" -eq 1 ]]; then
	echo "==> Enabling w4_sdca_trace via $MODCONF"
	echo 'options snd_soc_tas2783_sdw w4_sdca_trace=1' | sudo tee "$MODCONF" >/dev/null
else
	sudo rm -f "$MODCONF"
fi

cat <<EOF

==> W4 installed. Reboot, then:

1. Cold boot — speakers audible:
   speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
   sudo ./scripts/w4-trace-capture.sh --label pass-cold-playback

2. S2 — speakers silent:
   systemctl suspend && sleep 20
   speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
   sudo ./scripts/w4-trace-capture.sh --label fail-s2-playback

3. Diff lifecycle order:
   ./scripts/w4-trace-diff.sh validation/w4-trace-pass-cold-playback-* \\
                               validation/w4-trace-fail-s2-playback-*

Optional — every regmap_write / sdw_write / fw nwrite:
   sudo ./scripts/build-w4-trace.sh --sdca-trace && sudo reboot

Docs: research/experiments/w4-tas2783-trace-protocol.md
EOF
