#!/usr/bin/env bash
# Build/install phase-5 proposed tas2783 patches (trace + optional fix).
#
# Usage:
#   ./scripts/build-phase5-proposed.sh              # 0001 + 0002
#   ./scripts/build-phase5-proposed.sh --trace-only # 0001 only (observation)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
PROPOSED="$REPO_ROOT/research/phase-5/proposed"
STAMP="$SRC/.snd-repair-phase5-proposed"
TRACE_ONLY=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--trace-only) TRACE_ONLY=1; shift ;;
	-h|--help)
		echo "Usage: $0 [--trace-only]"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

cd "$SRC"

if [[ -f "$STAMP" ]]; then
	echo "==> Re-applying from upstream base (prior phase5 stamp found)"
	"$SCRIPT_DIR/reset-kernel-tree.sh"
	"$SCRIPT_DIR/apply-upstream-patches.sh"
	rm -f "$STAMP"
fi

if ! grep -q 'PHASE5 ctx=' sound/soc/codecs/tas2783-sdw.c 2>/dev/null; then
	echo "==> Applying 0001-phase5-pm-trace.patch"
	patch -p1 --forward -d "$SRC" <"$PROPOSED/0001-phase5-pm-trace.patch"

	if [[ "$TRACE_ONLY" -eq 0 ]]; then
		echo "==> Applying 0002-phase5-fw-reload-on-resume.patch"
		patch -p1 --forward -d "$SRC" <"$PROPOSED/0002-phase5-fw-reload-on-resume.patch"
	fi
else
	echo "==> PHASE5 already present in tas2783-sdw.c — skip patch apply"
fi

date -Is >"$STAMP"

echo "==> Building snd-soc-tas2783-sdw (phase5 proposed)"
make -C "$BUILD" M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules

ko="sound/soc/codecs/snd-soc-tas2783-sdw.ko"
name="$(basename "$ko")"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"
backup="$HOME/${name}.zst.orig"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

if strings "$ko" | grep -q PHASE5; then
	echo "OK: PHASE5 trace strings present in module"
else
	echo "WARN: PHASE5 strings not found — check patch apply" >&2
fi

if [[ ! -f "$backup" && -f "$dest" ]]; then
	echo "==> Backup: $backup"
	sudo cp "$dest" "$backup"
fi

zstd -19 -f "$ko" -o "/tmp/$name.zst"
echo "==> Installing $dest (requires sudo)"
sudo cp "/tmp/$name.zst" "$dest"
sudo depmod -a

echo ""
echo "==> Phase5 module installed for kernel $KVER"
if [[ "$TRACE_ONLY" -eq 0 ]]; then
	echo "Next: sudo reboot → suspend → resume →"
	echo "  journalctl -k -b 0 | grep PHASE5"
	echo "  ./scripts/phase5-resume-collect.sh --notes post-0002 --with-matrix"
else
	echo "Next: trace-only — suspend/resume and grep PHASE5 in dmesg"
fi
