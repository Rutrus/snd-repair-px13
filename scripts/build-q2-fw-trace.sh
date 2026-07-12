#!/usr/bin/env bash
# Build snd-soc-tas2783-sdw with upstream A+B+C + Q2 TAS2783Q2 trace probes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
Q2_PATCH="$REPO_ROOT/research/q2-fw-resume/patches/0001-tas2783-q2-resume-trace.patch"
Q2_STAMP="$SRC/.snd-repair-q2-fw-trace-applied"

if [[ ! -f "$SRC/Makefile" ]]; then
	echo "Run first: $SCRIPT_DIR/prepare-kernel-tree.sh" >&2
	exit 1
fi

if [[ -f "$SRC/.snd-repair-production-applied" ]]; then
	echo "Production patches on tree — reset: $SCRIPT_DIR/reset-kernel-tree.sh" >&2
	exit 1
fi

# Ensure upstream A+B+C (includes series B 0003)
if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

cd "$SRC"

if [[ ! -f "$Q2_STAMP" ]]; then
	echo "==> Applying Q2 trace patch"
	if patch -p1 --forward <"$Q2_PATCH"; then
		date -Is >"$Q2_STAMP"
	elif patch -p1 --reverse --dry-run <"$Q2_PATCH" >/dev/null 2>&1; then
		echo "    Q2 trace already applied"
		date -Is >"$Q2_STAMP"
	else
		echo "Failed to apply $Q2_PATCH" >&2
		echo "Regenerate: $SCRIPT_DIR/regenerate-q2-fw-trace-patch.sh" >&2
		exit 1
	fi
else
	echo "Q2 trace already applied ($(cat "$Q2_STAMP"))"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

echo "==> Building snd-soc-tas2783-sdw (upstream + Q2 trace)"
make -C "$BUILD" M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules

ko="sound/soc/codecs/snd-soc-tas2783-sdw.ko"
name="snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"
backup="$HOME/${name}.zst.orig"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

if [[ ! -f "$backup" && -f "$dest" ]]; then
	echo "==> Backup: $backup"
	sudo cp "$dest" "$backup"
fi

zstd -19 -f "$ko" -o "/tmp/$name.zst"
echo "==> Installing $dest"
sudo cp "/tmp/$name.zst" "$dest"
sudo depmod -a

echo ""
echo "==> Q2 trace module installed for $KVER"
echo "Reboot, then:"
echo "  journalctl -k -f | grep TAS2783Q2"
echo "  $SCRIPT_DIR/q2-fw-trace-collect.sh --label boot"
echo "Docs: research/q2-fw-resume/README.md"
