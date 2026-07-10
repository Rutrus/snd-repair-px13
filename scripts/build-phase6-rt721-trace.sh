#!/usr/bin/env bash
# Build/install Phase 6 RT721 PM trace module (observation only).
#
# Usage:
#   ./scripts/build-phase6-rt721-trace.sh
#
# Requires: linux-headers-$(uname -r), prepared KERNEL_SRC tree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
PROPOSED="$REPO_ROOT/research/phase-6/proposed"
STAMP="$SRC/.snd-repair-phase6-rt721-trace"
PATCH="$PROPOSED/0001-phase6-rt721-pm-trace.patch"

if [[ ! -f "$PATCH" ]]; then
	echo "Missing $PATCH" >&2
	exit 1
fi

if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

cd "$SRC"

if [[ -f "$STAMP" ]]; then
	echo "==> Re-applying from upstream base (prior phase6 RT721 stamp found)"
	"$SCRIPT_DIR/reset-kernel-tree.sh"
	"$SCRIPT_DIR/apply-upstream-patches.sh"
	rm -f "$STAMP"
fi

phase6_rt721_trace_present() {
	grep -q 'rt721_phase6_pm_trace' "$SRC/sound/soc/codecs/rt721-sdca-sdw.c" 2>/dev/null
}

cleanup_rejects() {
	rm -f "$SRC/sound/soc/codecs"/rt721-sdca*.rej
}

if phase6_rt721_trace_present; then
	echo "==> PHASE6 RT721 trace already present — skip patch apply"
	cleanup_rejects
else
	echo "==> Applying 0001-phase6-rt721-pm-trace.patch"
	if patch -p1 --forward -d "$SRC" <"$PATCH"; then
		cleanup_rejects
	elif phase6_rt721_trace_present; then
		echo "==> Patch reported already applied — continuing"
		cleanup_rejects
	else
		echo "ERROR: patch failed and PHASE6 trace not in tree" >&2
		echo "  See $SRC/sound/soc/codecs/*.rej" >&2
		exit 1
	fi
fi

date -Is >"$STAMP"

echo "==> Building snd-soc-rt721-sdca (phase6 RT721 trace)"
make -C "$BUILD" M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_RT721_SDCA_SDW=m modules

ko="sound/soc/codecs/snd-soc-rt721-sdca.ko"
name="$(basename "$ko")"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"
backup="$HOME/${name}.zst.orig"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

if strings "$ko" | grep -qE 'PHASE6 ctx=pm|resume_enter'; then
	echo "OK: PHASE6 RT721 trace strings present in module"
else
	echo "WARN: PHASE6 strings not found — check patch apply" >&2
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
echo "==> Phase6 RT721 trace module installed for kernel $KVER"
echo "Next:"
echo "  sudo reboot"
echo "  ./scripts/phase6-experiment.sh baseline --notes pre-rt721-trace"
echo "  PHASE6_SKIP_PX13=1 ./scripts/phase6-experiment.sh arm --notes run-N"
echo "  systemctl suspend"
echo "  journalctl -k -b 0 | grep 'PHASE6 ctx='"
