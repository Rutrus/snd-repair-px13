#!/usr/bin/env bash
# Build/install Phase 6 SoundWire bus trace module (observation only).
#
# Usage:
#   ./scripts/build-phase6-sdw-trace.sh
#
# Traces: unattach_request, reinit/complete, update_status dispatch, attach skip paths.
# Does not replace RT721 trace — install both for full picture.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
PATCH="$REPO_ROOT/research/phase-6/proposed/0002-phase6-sdw-bus-trace.patch"
STAMP="$SRC/.snd-repair-phase6-sdw-trace"

[[ -f "$PATCH" ]] || { echo "Missing $PATCH" >&2; exit 1; }

if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

cd "$SRC"

phase6_sdw_trace_present() {
	grep -q 'sdw_phase6_state_change' "$SRC/drivers/soundwire/bus.c" 2>/dev/null
}

cleanup_rejects() {
	rm -f "$SRC/drivers/soundwire/bus.c.rej"
}

if [[ -f "$STAMP" ]]; then
	echo "==> Re-applying from upstream base (prior phase6 SDW stamp found)"
	"$SCRIPT_DIR/reset-kernel-tree.sh"
	"$SCRIPT_DIR/apply-upstream-patches.sh"
	rm -f "$STAMP"
fi

if phase6_sdw_trace_present; then
	echo "==> PHASE6 SDW bus trace already present — skip patch apply"
	cleanup_rejects
else
	echo "==> Applying 0002-phase6-sdw-bus-trace.patch"
	if patch -p1 --forward -d "$SRC" <"$PATCH"; then
		cleanup_rejects
	elif phase6_sdw_trace_present; then
		echo "==> Patch reported already applied — continuing"
		cleanup_rejects
	else
		echo "ERROR: SDW patch failed" >&2
		exit 1
	fi
fi

date -Is >"$STAMP"

echo "==> Building soundwire-bus (phase6 SDW trace)"
make -C "$BUILD" M="$(pwd)/drivers/soundwire" CONFIG_SOUNDWIRE=m modules

ko="drivers/soundwire/soundwire-bus.ko"
name="$(basename "$ko")"
dest="/lib/modules/$KVER/kernel/drivers/soundwire/${name}.zst"
backup="$HOME/${name}.zst.orig"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

if strings "$ko" | grep -qE 'PHASE6 ctx=sdw fn=state_change|fn=completion'; then
	echo "OK: PHASE6 SDW trace strings present"
else
	echo "WARN: PHASE6 SDW strings not found" >&2
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
echo "==> Phase6 soundwire-bus installed for kernel $KVER"
echo "Tip: keep snd-soc-rt721-sdca PHASE6 module installed for codec-side wait timeline."
echo "Next: sudo reboot → suspend/resume →"
echo "  journalctl -k -b 0 | grep 'PHASE6 ctx=sdw fn='"
