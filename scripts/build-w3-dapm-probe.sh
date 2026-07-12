#!/usr/bin/env bash
# W3 — DAPM diagnostic on snd-soc-tas2783-sdw (requires upstream B + W2).
#
# Phase A (default): instrumentation only (w3_dapm_sync_probe=0)
# Phase B: also snd_soc_dapm_sync after fw_reinit (module param)
#
# Usage:
#   sudo ./scripts/build-w3-dapm-probe.sh
#   sudo reboot
#
# After S2 (Experiment A — trace only):
#   journalctl -k -b 0 | grep 'W3 ctx='
#
# Experiment B — enable sync probe before S2:
#   echo 1 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe
#   systemctl suspend
#   speaker-test -D hw:1,2 -c 2 -t sine -f 440 -l 1
#   journalctl -k -b 0 | grep 'W3 ctx='
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

W3_PATCH="$REPO_ROOT/research/make-it-work/patches/w3-dapm-diagnostic.patch"
W3_STAMP="$KERNEL_SRC/.snd-repair-w3-dapm-applied"

W2_ARGS=(--skip-install)
for arg in "$@"; do
	case "$arg" in
	--trace) W2_ARGS+=(--trace) ;;
	--skip-install) ;;
	-h|--help) ;;
	*) W2_ARGS+=("$arg") ;;
	esac
done
"$SCRIPT_DIR/build-w2-force-fw.sh" "${W2_ARGS[@]}"

cd "$KERNEL_SRC"
C_SRC="$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"

if grep -Fq 'W3 ctx=dapm fn=fu21_event' "$C_SRC"; then
	echo "==> W3 dapm diagnostic already in source — skipping patch"
	date -Is >"$W3_STAMP"
elif patch -p1 --forward <"$W3_PATCH"; then
	date -Is >"$W3_STAMP"
else
	echo "Failed to apply $W3_PATCH" >&2
	echo "If W3 is already present, ensure 'W3 ctx=dapm fn=fu21_event' is in $C_SRC" >&2
	exit 1
fi

grep -Fq 'W3 ctx=dapm fn=fu21_event' "$C_SRC" || { echo "W3 not in source" >&2; exit 1; }
grep -Fq 'tas2783_w3_after_fw_reinit' "$C_SRC" || { echo "W3 helpers missing in source" >&2; exit 1; }

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
CODEC_DIR="$KERNEL_SRC/sound/soc/codecs"
KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
name="snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"

echo "==> Rebuilding snd-soc-tas2783-sdw (B + W2 + W3)"
rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.o \
	"$CODEC_DIR"/snd-soc-tas2783-sdw.ko "$CODEC_DIR"/.tas2783-sdw.o.cmd \
	"$CODEC_DIR"/.snd-soc-tas2783-sdw.ko.cmd
make -C "$BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules

[[ -f "$KO" ]] || { echo "Missing $KO" >&2; exit 1; }

# grep -a on the .ko directly — avoids pipefail/SIGPIPE false negatives from strings|grep
if grep -aFq 'W3 ctx=dapm fn=fu21_event' "$KO" 2>/dev/null; then
	echo "OK: W3 present in source + module"
elif grep -aFq 'parm=w3_dapm_sync_probe' "$KO" 2>/dev/null; then
	echo "OK: W3 present in source + module (param string)"
else
	echo "ERROR: W3 not present in $KO (source has W3 — clean rebuild failed)" >&2
	echo "  Debug: grep -a W3 '$KO'" >&2
	exit 1
fi

zstd -19 -f "$KO" -o "/tmp/$name.zst"
echo "==> Installing $dest"
sudo cp "/tmp/$name.zst" "$dest"
sudo depmod -a

cat <<EOF

==> W3 installed. Reboot, then:

Experiment A (instrumentation only):
  systemctl suspend && sleep 20
  speaker-test -D hw:1,2 -c 2 -t sine -f 440 -l 1
  journalctl -k -b 0 | grep 'W3 ctx='

Experiment B (add dapm_sync after fw_reinit):
  echo 1 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe
  systemctl suspend && sleep 20
  speaker-test -D hw:1,2 -c 2 -t sine -f 440 -l 1

Docs: research/experiments/w3-dapm-diagnostic-protocol.md
EOF
