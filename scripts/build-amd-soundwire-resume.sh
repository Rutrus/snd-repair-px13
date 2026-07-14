#!/usr/bin/env bash
# Build/install AMD SoundWire manager resume fix (IRQ worker kick after S2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PATCH="$REPO_ROOT/patches/0002-amd-soundwire-resume-irq-kick.patch"
AMD_C="$KERNEL_SRC/drivers/soundwire/amd_manager.c"
AMD_DIR="$KERNEL_SRC/drivers/soundwire"

ensure_kernel_tree_writable "$KERNEL_SRC"

if ! grep -q 'amd_sdw_kick_irq_if_pending' "$AMD_C" 2>/dev/null; then
	echo "==> Applying $PATCH"
	patch -p1 --forward -d "$KERNEL_SRC" <"$PATCH" || {
		grep -q 'amd_sdw_kick_irq_if_pending' "$AMD_C" || {
			echo "ERROR: AMD resume patch failed" >&2
			exit 1
		}
	}
fi

KVER="$(uname -r)"
KO="$AMD_DIR/soundwire-amd.ko"
dest="/lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst"

rm -f "$AMD_DIR"/amd_manager.o "$AMD_DIR"/soundwire-amd.ko
make -C "$KERNEL_BUILD" M="$AMD_DIR" CONFIG_SOUNDWIRE=m CONFIG_SOUNDWIRE_AMD=m modules
strings "$KO" | grep -q 'amd_sdw_kick_irq_if_pending' || {
	echo "ERROR: patch marker missing in $KO" >&2
	exit 1
}

zstd -f "$KO" -o "/tmp/soundwire-amd.ko.zst"
[[ $EUID -eq 0 ]] && cp "/tmp/soundwire-amd.ko.zst" "$dest" && depmod -a || \
	sudo cp "/tmp/soundwire-amd.ko.zst" "$dest" && sudo depmod -a

echo "AMD SoundWire resume fix installed. Reboot, then validate S2 → wpctl status."
