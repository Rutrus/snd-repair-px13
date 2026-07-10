#!/usr/bin/env bash
# Build/install Phase 6 AMD SoundWire manager trace module (observation only).
#
# Usage:
#   ./scripts/build-phase6-amd-trace.sh
#
# Traces: resume_enter (pm=system|runtime), ping_status, queue_work, handle_status.
# Install alongside soundwire-bus + rt721 PHASE6 modules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
PATCH="$REPO_ROOT/research/phase-6/proposed/0003-phase6-amd-sdw-trace.patch"
PATCH4="$REPO_ROOT/research/phase-6/proposed/0004-phase6-amd-minimal-irq-trace.patch"
PATCH5="$REPO_ROOT/research/phase-6/proposed/0005-phase6-s1-s2-bisect.patch"
STAMP="$SRC/.snd-repair-phase6-amd-trace"
STAMP4="$SRC/.snd-repair-phase6-amd-irq-trace"
STAMP5="$SRC/.snd-repair-phase6-s1s2-trace"

[[ -f "$PATCH" ]] || { echo "Missing $PATCH" >&2; exit 1; }
[[ -f "$PATCH4" ]] || { echo "Missing $PATCH4" >&2; exit 1; }
[[ -f "$PATCH5" ]] || { echo "Missing $PATCH5" >&2; exit 1; }

if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

cd "$SRC"

phase6_amd_trace_present() {
	grep -q 'amd_phase6_status_name' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
}

phase6_amd_irq_trace_present() {
	grep -q 'fn=irq_enabled' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
}

phase6_amd_hw_trace_present() {
	grep -q 'fn=intr_stat_post_enable' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
}

cleanup_rejects() {
	rm -f "$SRC/drivers/soundwire/amd_manager.c.rej"
	rm -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej"
}

if [[ -f "$STAMP" ]]; then
	echo "==> Re-applying from upstream base (prior phase6 AMD stamp found)"
	"$SCRIPT_DIR/reset-kernel-tree.sh"
	"$SCRIPT_DIR/apply-upstream-patches.sh"
	rm -f "$STAMP" "$STAMP4" "$STAMP5"
fi

if phase6_amd_trace_present; then
	echo "==> PHASE6 AMD trace (0003) already present — skip patch apply"
	cleanup_rejects
else
	echo "==> Applying 0003-phase6-amd-sdw-trace.patch"
	if patch -p1 --forward -d "$SRC" <"$PATCH"; then
		cleanup_rejects
	elif phase6_amd_trace_present; then
		echo "==> Patch reported already applied — continuing"
		cleanup_rejects
	else
		echo "ERROR: AMD patch 0003 failed" >&2
		exit 1
	fi
fi

if phase6_amd_irq_trace_present; then
	echo "==> PHASE6 AMD IRQ trace (0004) already present — skip"
	cleanup_rejects
else
	echo "==> Applying 0004-phase6-amd-minimal-irq-trace.patch"
	if patch -p1 --forward -d "$SRC" <"$PATCH4"; then
		cleanup_rejects
	elif phase6_amd_irq_trace_present; then
		echo "==> Patch 0004 reported already applied — continuing"
		cleanup_rejects
	else
		echo "ERROR: AMD patch 0004 failed" >&2
		exit 1
	fi
fi

if phase6_amd_hw_trace_present; then
	echo "==> PHASE6 S1/S2 trace (0005) already present — skip"
	cleanup_rejects
else
	echo "==> Applying 0005-phase6-s1-s2-bisect.patch"
	if patch -p1 --forward -d "$SRC" <"$PATCH5"; then
		cleanup_rejects
	elif phase6_amd_hw_trace_present; then
		echo "==> Patch 0005 reported already applied — continuing"
		cleanup_rejects
	else
		echo "ERROR: AMD patch 0005 failed" >&2
		exit 1
	fi
fi

date -Is >"$STAMP"
date -Is >"$STAMP4"
date -Is >"$STAMP5"

echo "==> Building soundwire-amd + snd-pci-ps (phase6 AMD/ACP trace)"
make -C "$BUILD" M="$(pwd)/drivers/soundwire" CONFIG_SOUNDWIRE=m CONFIG_SOUNDWIRE_AMD=m modules
make -C "$BUILD" M="$(pwd)/sound/soc/amd/ps" CONFIG_SND_SOC_AMD_PS=m modules

ko="drivers/soundwire/soundwire-amd.ko"
ko_ps="sound/soc/amd/ps/snd-pci-ps.ko"
name="$(basename "$ko")"
name_ps="$(basename "$ko_ps")"
dest="/lib/modules/$KVER/kernel/drivers/soundwire/${name}.zst"
dest_ps="/lib/modules/$KVER/kernel/sound/soc/amd/ps/${name_ps}.zst"
backup="$HOME/${name}.zst.orig"
backup_ps="$HOME/${name_ps}.zst.orig"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }
[[ -f "$ko_ps" ]] || { echo "Missing $ko_ps" >&2; exit 1; }

if strings "$ko" | grep -q 'fn=intr_stat_post_enable'; then
	echo "OK: PHASE6 S1/S2 bisect strings present"
elif strings "$ko" | grep -qE 'fn=irq_enabled|fn=ping_irq'; then
	echo "OK: PHASE6 AMD IRQ trace strings present (0004 only — rebuild for 0005)"
else
	echo "WARN: PHASE6 AMD IRQ strings not found" >&2
fi

if strings "$ko_ps" | grep -q 'fn=irq_handler_enter'; then
	echo "OK: PHASE6 ACP irq_handler_enter present"
elif strings "$ko_ps" | grep -q 'fn=sdw0_irq'; then
	echo "OK: PHASE6 ACP sdw0_irq string present (0004 only)"
else
	echo "WARN: PHASE6 ACP strings not found" >&2
fi

if [[ ! -f "$backup" && -f "$dest" ]]; then
	echo "==> Backup: $backup"
	sudo cp "$dest" "$backup"
fi
if [[ ! -f "$backup_ps" && -f "$dest_ps" ]]; then
	echo "==> Backup: $backup_ps"
	sudo cp "$dest_ps" "$backup_ps"
fi

zstd -19 -f "$ko" -o "/tmp/$name.zst"
zstd -19 -f "$ko_ps" -o "/tmp/$name_ps.zst"
echo "==> Installing $dest and $dest_ps (requires sudo)"
sudo cp "/tmp/$name.zst" "$dest"
sudo cp "/tmp/$name_ps.zst" "$dest_ps"
sudo depmod -a

echo ""
echo "==> Phase6 soundwire-amd + snd-pci-ps installed for kernel $KVER"
echo "Next: sudo reboot → suspend/resume →"
echo "  journalctl -k -b 0 | grep -E 'PHASE6 ctx=(amd|acp) fn='"
