#!/usr/bin/env bash
# Build/install Phase 7 AMD SoundWire experiment on Phase 6 trace base.
#
# Usage:
#   ./scripts/build-phase7.sh --experiment delay-after-d0
#   ./scripts/build-phase7.sh --experiment delay-after-d0 --delay 20
#   PHASE7_EXPERIMENT=delay-after-d0 PHASE7_DELAY_MS=20 ./scripts/build-phase7.sh
#
# Phase 6 observation patches (0003–0007) are applied first, then ONE Phase 7 patch.
# Set phase7_delay_ms via sysfs before suspend (default 0 = control).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
EXPERIMENT="${PHASE7_EXPERIMENT:-}"
DELAY_MS="${PHASE7_DELAY_MS:-}"
STAMP_P7="$SRC/.snd-repair-phase7-experiment"

usage() {
	cat <<EOF
Usage:
  $0 --experiment NAME [--delay MS]

Experiments:
  delay-after-d0   module param phase7_delay_ms (0=control; try 5,10,20,50,100)

Environment:
  PHASE7_EXPERIMENT   same as --experiment
  PHASE7_DELAY_MS     suggested value (written to state file; set on module before suspend)

After install:
  echo MS | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--experiment) EXPERIMENT="${2:?}"; shift 2 ;;
	--delay) DELAY_MS="${2:?}"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown: $1" >&2; usage; exit 1 ;;
	esac
done

[[ -n "$EXPERIMENT" ]] || { usage; exit 1; }

phase7_patch_for() {
	case "$1" in
	delay-after-d0)
		echo "$REPO_ROOT/research/phase-7/proposed/0005-delay-after-d0.patch"
		;;
	*)
		echo "Unknown experiment: $1" >&2
		exit 1
		;;
	esac
}

phase7_present() {
	case "$1" in
	delay-after-d0)
		grep -q 'fn=delay_after_D0' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
		;;
	*) return 1 ;;
	esac
}

PATCH_P7="$(phase7_patch_for "$EXPERIMENT")"
[[ -f "$PATCH_P7" ]] || { echo "Missing $PATCH_P7" >&2; exit 1; }

if [[ -f "$STAMP_P7" ]] && [[ "$(cat "$STAMP_P7")" != "$EXPERIMENT" ]]; then
	echo "==> Phase 7 experiment switch: $(cat "$STAMP_P7") → $EXPERIMENT (reset tree)"
	"$SCRIPT_DIR/reset-kernel-tree.sh"
	"$SCRIPT_DIR/apply-upstream-patches.sh"
	rm -f "$SRC"/.snd-repair-phase6-*
fi

echo "==> Phase 6 trace base (0003–0007)"
"$SCRIPT_DIR/build-phase6-amd-trace.sh"

cd "$SRC"
if phase7_present "$EXPERIMENT"; then
	echo "==> Phase 7 $EXPERIMENT already present — skip patch"
else
	echo "==> Applying Phase 7: $EXPERIMENT"
	if patch -p1 --forward -d "$SRC" <"$PATCH_P7"; then
		:
	elif phase7_present "$EXPERIMENT"; then
		echo "==> Patch reported already applied"
	else
		echo "ERROR: Phase 7 patch failed" >&2
		exit 1
	fi
fi

echo "$EXPERIMENT" >"$STAMP_P7"
date -Is >>"$STAMP_P7"

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
echo "==> Rebuilding soundwire-amd (Phase 7 $EXPERIMENT)"
make -C "$BUILD" M="$(pwd)/drivers/soundwire" CONFIG_SOUNDWIRE=m CONFIG_SOUNDWIRE_AMD=m modules

ko="drivers/soundwire/soundwire-amd.ko"
name="$(basename "$ko")"
dest="/lib/modules/$KVER/kernel/drivers/soundwire/${name}.zst"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

if strings "$ko" | grep -q 'phase7_delay_ms'; then
	echo "OK: phase7_delay_ms module param present"
else
	echo "WARN: phase7_delay_ms not in module" >&2
fi

zstd -19 -f "$ko" -o "/tmp/$name.zst"
echo "==> Installing $dest (requires sudo)"
sudo cp "/tmp/$name.zst" "$dest"
sudo depmod -a

STATE="${REPO_ROOT}/validation/.state"
mkdir -p "$STATE"
echo "${DELAY_MS:-0}" >"${STATE}/phase7-delay-ms-suggested"
echo "$EXPERIMENT" >"${STATE}/phase7-experiment"

echo ""
echo "==> Phase 7 installed: $EXPERIMENT on kernel $KVER"
echo "Reboot required if module was already loaded."
echo ""
echo "Before suspend (0 = control baseline):"
echo "  echo ${DELAY_MS:-0} | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms"
echo ""
echo "Sweep: 0, 5, 10, 20, 50, 100 — see research/phase-7/experiments/0005-delay-after-d0.md"
echo "Run:  /home/rutrus/snd_repair/scripts/phase6-hunt.sh post-reboot --notes p7-0005-delay\${MS}"
