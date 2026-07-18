#!/usr/bin/env bash
# Build/install AMD SoundWire manager resume fix (IRQ worker kick after S2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PATCH="$REPO_ROOT/patches/0002-amd-soundwire-resume-irq-kick.patch"
AMD_C="$KERNEL_SRC/drivers/soundwire/amd_manager.c"
AMD_DIR="$KERNEL_SRC/drivers/soundwire"

ko_has_0002_marker() {
	[[ -f "$1" ]] && grep -aq 'amd_sdw_kick_irq_if_pending' "$1"
}

ensure_kernel_tree_writable "$KERNEL_SRC"

if grep -qE 'PHASE7|snd_repair_phase7|manual_irq_schedule' "$AMD_C" 2>/dev/null; then
	echo "ERROR: amd_manager.c still has lab (phase7) markers." >&2
	echo "  Run: sudo ./scripts/reset-kernel-tree.sh" >&2
	exit 1
fi

if ! grep -q 'amd_sdw_kick_irq_if_pending' "$AMD_C" 2>/dev/null; then
	echo "==> Applying $PATCH"
	patch -p1 --forward -d "$KERNEL_SRC" <"$PATCH" || {
		grep -q 'amd_sdw_kick_irq_if_pending' "$AMD_C" || {
			echo "ERROR: AMD resume patch failed" >&2
			exit 1
		}
	}
fi

grep -q 'amd_sdw_kick_irq_if_pending(amd_manager)' "$AMD_C" || {
	echo "ERROR: 0002 call site missing in amd_manager.c (partial patch?)" >&2
	echo "  Run: sudo ./scripts/reset-kernel-tree.sh && re-apply patches" >&2
	exit 1
}

KVER="$(uname -r)"
KO="$AMD_DIR/soundwire-amd.ko"
dest="/lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst"

echo "==> Clean rebuild soundwire-amd (drop stale .o)"
rm -f "$AMD_DIR"/amd_manager.o "$AMD_DIR"/soundwire-amd.o "$AMD_DIR"/soundwire-amd.ko \
	"$AMD_DIR"/.amd_manager.o.cmd "$AMD_DIR"/.soundwire-amd.o.cmd \
	"$AMD_DIR"/.soundwire-amd.ko.cmd

make -C "$KERNEL_BUILD" M="$AMD_DIR" CONFIG_SOUNDWIRE=m CONFIG_SOUNDWIRE_AMD=m modules

if ! ko_has_0002_marker "$KO"; then
	echo "ERROR: 0002 marker not found in $KO" >&2
	echo "  amd_manager.c has the patch; rebuild artifact looks wrong." >&2
	echo "  Try: sudo ./scripts/reset-kernel-tree.sh && full rebuild from apply-upstream-patches.sh" >&2
	exit 1
fi

zstd -f "$KO" -o "/tmp/soundwire-amd.ko.zst"
if [[ $EUID -eq 0 ]]; then
	cp "/tmp/soundwire-amd.ko.zst" "$dest"
	depmod -a
else
	sudo cp "/tmp/soundwire-amd.ko.zst" "$dest"
	sudo depmod -a
fi

echo "AMD SoundWire resume fix installed to $dest"
echo "Reboot, then verify:"
echo "  zstdcat $dest | strings | grep amd_sdw_kick_irq_if_pending && echo '0002 OK'"
