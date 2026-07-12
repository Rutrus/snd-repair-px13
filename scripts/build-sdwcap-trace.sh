#!/usr/bin/env bash
# Build/install SDWCAP trace — all stream->state transitions in stream.c
#
# Usage:
#   sudo ./scripts/build-sdwcap-trace.sh
#   sudo reboot
#
# Experiment (post-S2):
#   systemctl suspend && sleep 45
#   systemctl --user stop wireplumber pipewire pipewire-pulse
#   speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1
#   arecord -D hw:1,3 -f S16_LE -r 48000 -c 2 -d 1 /tmp/cap.wav
#   journalctl -k --since "5 minutes ago" | grep SDWCAP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
PATCH="$REPO_ROOT/research/capture-sdw/patches/0001-sdwcap-stream-state-trace.patch"
STAMP="$SRC/.snd-repair-sdwcap-trace"

[[ -f "$PATCH" ]] || { echo "Missing $PATCH" >&2; exit 1; }

if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

cd "$SRC"

sdwcap_present() {
	grep -q 'sdwcap_stream_set_state' "$SRC/drivers/soundwire/stream.c" 2>/dev/null
}

if [[ -f "$STAMP" ]]; then
	echo "==> Re-applying from upstream base (prior SDWCAP stamp)"
	"$SCRIPT_DIR/reset-kernel-tree.sh"
	"$SCRIPT_DIR/apply-upstream-patches.sh"
	rm -f "$STAMP"
fi

if sdwcap_present; then
	echo "==> SDWCAP trace already present — skip patch"
else
	echo "==> Applying 0001-sdwcap-stream-state-trace.patch"
	if patch -p1 --forward -d "$SRC" <"$PATCH"; then
		rm -f "$SRC/drivers/soundwire/stream.c.rej"
	elif sdwcap_present; then
		echo "==> Already applied"
	else
		echo "ERROR: SDWCAP patch failed — check stream.c.rej" >&2
		exit 1
	fi
fi

date -Is >"$STAMP"

echo "==> Building soundwire-bus (SDWCAP)"
make -C "$BUILD" M="$(pwd)/drivers/soundwire" CONFIG_SOUNDWIRE=m modules

ko="drivers/soundwire/soundwire-bus.ko"
name="$(basename "$ko")"
dest="/lib/modules/$KVER/kernel/drivers/soundwire/${name}.zst"
backup="$HOME/${name}.sdwcap.zst.orig"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

if strings "$ko" | grep -q 'SDWCAP trans'; then
	echo "OK: SDWCAP strings present"
else
	echo "WARN: SDWCAP strings not found" >&2
fi

if [[ ! -f "$backup" && -f "$dest" ]]; then
	echo "==> Backup: $backup"
	sudo cp "$dest" "$backup"
fi

zstd -19 -f "$ko" -o "/tmp/$name.zst"
echo "==> Installing $dest"
sudo cp "/tmp/$name.zst" "$dest"
sudo depmod -a

echo ""
echo "==> SDWCAP soundwire-bus installed for $KVER"
echo "Docs: research/capture-sdw/INSTRUMENTATION-PLAN.md"
echo "Next: reboot → S2 → play then capture → journalctl -k | grep SDWCAP"
