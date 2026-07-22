#!/usr/bin/env bash
# Build AMD SoundWire resume fix: 0002 (IRQ kick) + 0003 (force ping) + 0003b (delayed re-kick).
# Stages to build/staging/$KVER — does not write /lib/modules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/modules.sh
source "$SCRIPT_DIR/lib/modules.sh"

PATCH_0002="$REPO_ROOT/patches/0002-amd-soundwire-resume-irq-kick.patch"
PATCH_0003="$REPO_ROOT/patches/0003-amd-soundwire-resume-force-ping.patch"
PATCH_0003B="$REPO_ROOT/patches/0003b-amd-soundwire-resume-delayed-enum-kick.patch"
AMD_C="$KERNEL_SRC/drivers/soundwire/amd_manager.c"
AMD_DIR="$KERNEL_SRC/drivers/soundwire"

ko_has_0002_marker() {
	[[ -f "$1" ]] && grep -aq 'amd_sdw_kick_irq_if_pending' "$1"
}

ko_has_0003_marker() {
	[[ -f "$1" ]] && grep -aq 'snd_repair resume enum kick' "$1"
}

ko_has_0003b_marker() {
	[[ -f "$1" ]] && grep -aq 'snd_repair resume enum kick delayed' "$1"
}

ensure_kernel_tree_writable "$KERNEL_SRC"

if grep -qE 'PHASE7|snd_repair_phase7|manual_irq_schedule' "$AMD_C" 2>/dev/null; then
	echo "ERROR: amd_manager.c still has lab (phase7) markers." >&2
	echo "  Run: $SCRIPT_DIR/reset-kernel-tree.sh" >&2
	exit 1
fi

if ! grep -q 'amd_sdw_kick_irq_if_pending' "$AMD_C" 2>/dev/null; then
	echo "==> Applying $PATCH_0002"
	patch -p1 --forward -d "$KERNEL_SRC" <"$PATCH_0002" || {
		grep -q 'amd_sdw_kick_irq_if_pending' "$AMD_C" || {
			echo "ERROR: AMD resume patch 0002 failed" >&2
			exit 1
		}
	}
fi

if ! grep -q 'snd_repair resume enum kick' "$AMD_C" 2>/dev/null; then
	echo "==> Applying $PATCH_0003"
	patch -p1 --forward -d "$KERNEL_SRC" <"$PATCH_0003" || {
		grep -q 'snd_repair resume enum kick' "$AMD_C" || {
			echo "ERROR: AMD resume patch 0003 failed" >&2
			exit 1
		}
	}
fi

if ! grep -q 'amd_sdw_enum_retry_works' "$AMD_C" 2>/dev/null; then
	echo "==> Applying $PATCH_0003B"
	patch -p1 --forward -d "$KERNEL_SRC" <"$PATCH_0003B" || {
		grep -q 'amd_sdw_enum_retry_works' "$AMD_C" || {
			echo "ERROR: AMD resume patch 0003b failed" >&2
			exit 1
		}
	}
fi

grep -q 'amd_sdw_kick_irq_if_pending(amd_manager)' "$AMD_C" || {
	echo "ERROR: 0002 call site missing in amd_manager.c (partial patch?)" >&2
	echo "  Run: $SCRIPT_DIR/reset-kernel-tree.sh && re-apply patches" >&2
	exit 1
}

grep -q 'amd_sdw_read_and_process_ping_status(amd_manager)' "$AMD_C" || {
	echo "ERROR: 0003 ping call missing in kick helper" >&2
	exit 1
}

grep -q 'schedule_delayed_work(&amd_sdw_enum_retry_works' "$AMD_C" || {
	echo "ERROR: 0003b delayed schedule missing" >&2
	exit 1
}

KO="$AMD_DIR/soundwire-amd.ko"

echo "==> Clean rebuild soundwire-amd (drop stale .o)"
rm -f "$AMD_DIR"/amd_manager.o "$AMD_DIR"/soundwire-amd.o "$AMD_DIR"/soundwire-amd.ko \
	"$AMD_DIR"/.amd_manager.o.cmd "$AMD_DIR"/.soundwire-amd.o.cmd \
	"$AMD_DIR"/.soundwire-amd.ko.cmd

make -C "$KERNEL_BUILD" M="$AMD_DIR" CONFIG_SOUNDWIRE=m CONFIG_SOUNDWIRE_AMD=m modules

if ! ko_has_0002_marker "$KO"; then
	echo "ERROR: 0002 marker not found in $KO" >&2
	exit 1
fi
if ! ko_has_0003_marker "$KO"; then
	echo "ERROR: 0003 marker not found in $KO" >&2
	exit 1
fi
if ! ko_has_0003b_marker "$KO"; then
	echo "ERROR: 0003b marker not found in $KO" >&2
	exit 1
fi

stage_ko "$KO"

echo "0002+0003+0003b staged. Install overlay:"
echo "  sudo $SCRIPT_DIR/snd-repair install-modules"
echo "  sudo reboot   # prefer cold power if bus already UNATTACHED"
echo "After reboot: one S2, then:"
echo "  grep . /sys/bus/soundwire/devices/sdw:*/status"
echo "  journalctl -k -b 0 | grep 'snd_repair resume enum kick'"
