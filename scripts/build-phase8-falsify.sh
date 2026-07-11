#!/usr/bin/env bash
# Phase 8.2 — apply ONE falsification patch on Phase 8 observation base.
#
# Usage:
#   ./scripts/build-phase8-falsify.sh --patch B
#   ./scripts/build-phase8-falsify.sh --patch E|D
#
# Order after A (failed): B → E → D. One patch per reboot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
PATCH_ID="${PHASE8_FALSIFY_PATCH:-}"
STAMP="$SRC/.snd-repair-phase8-falsify"
PROPOSED="$REPO_ROOT/research/phase-8/proposed"

usage() {
	cat <<EOF
Usage: $0 --patch A|B|E|D

Recommended order after patch A (failed): B → E → D.

Rebuilds snd-pci-ps with exactly one 0009 falsification patch on Phase 6/7/8 base.
Runs restore-ps-falsify.sh before apply (strips prior 0009 hunks).
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--patch) PATCH_ID="${2:?}"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown: $1" >&2; usage; exit 1 ;;
	esac
done

PATCH_ID="${PATCH_ID^^}"
case "$PATCH_ID" in
A) PATCH_FILE="$PROPOSED/0009a-stat1-preclear.patch" ;;
B) PATCH_FILE="$PROPOSED/0009b-intr-block-reset.patch" ;;
E) PATCH_FILE="$PROPOSED/0009e-enable-irq-resume.patch" ;;
D) PATCH_FILE="$PROPOSED/0009d-pci-set-master-resume.patch" ;;
C) PATCH_FILE="$PROPOSED/0009c-pme-before-enable.patch" ;;
*) echo "ERROR: --patch must be A, B, E, D (or C)" >&2; exit 1 ;;
esac

[[ -f "$PATCH_FILE" ]] || { echo "Missing $PATCH_FILE" >&2; exit 1; }

echo "==> Phase 8 observation base (0007 + 0008)"
"$SCRIPT_DIR/build-phase8.sh"

cd "$SRC"

echo "==> Restore ps-common.c / pci-ps.c (strip prior 0009 hunks)"
chmod +x "$SCRIPT_DIR/restore-ps-falsify.sh"
"$SCRIPT_DIR/restore-ps-falsify.sh"

if grep -q 'PHASE9 ctx=acp fn=falsify patch='"$PATCH_ID" "$SRC/sound/soc/amd/ps/ps-common.c" \
	"$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null; then
	echo "==> Patch $PATCH_ID already present in tree"
else
	if grep -q 'PHASE9 ctx=acp fn=falsify patch=' "$SRC/sound/soc/amd/ps/ps-common.c" \
		"$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null; then
		echo "ERROR: another 0009 patch still present — run restore-ps-falsify.sh" >&2
		exit 1
	fi
	echo "==> Applying falsification patch $PATCH_ID"
	rm -f "$SRC/sound/soc/amd/ps/ps-common.c.rej" "$SRC/sound/soc/amd/ps/pci-ps.c.rej"
	patch -p1 --forward -d "$SRC" <"$PATCH_FILE" || {
		[[ -f "$SRC/sound/soc/amd/ps/ps-common.c.rej" ]] && cat "$SRC/sound/soc/amd/ps/ps-common.c.rej" >&2
		[[ -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej" ]] && cat "$SRC/sound/soc/amd/ps/pci-ps.c.rej" >&2
		echo "ERROR: patch $PATCH_ID failed" >&2
		exit 1
	}
fi

echo "patch=$PATCH_ID" >"$STAMP"
date -Is >>"$STAMP"

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
echo "==> Rebuilding snd-pci-ps (Phase 8.2 falsify $PATCH_ID)"
kernel_make_pci_ps_modules

ko_ps="sound/soc/amd/ps/snd-pci-ps.ko"
dest_ps="/lib/modules/$KVER/kernel/sound/soc/amd/ps/snd-pci-ps.ko.zst"
[[ -f "$ko_ps" ]] || { echo "Missing $ko_ps" >&2; exit 1; }

if strings "$ko_ps" | grep -q "PHASE9 ctx=acp fn=falsify patch=$PATCH_ID"; then
	echo "OK: falsify patch $PATCH_ID string present"
else
	echo "WARN: PHASE9 patch $PATCH_ID string missing in ko" >&2
fi

name_ps="$(basename "$ko_ps")"
zstd -19 -f "$ko_ps" -o "/tmp/$name_ps.zst"
echo "==> Installing $dest_ps (requires sudo)"
sudo cp "/tmp/$name_ps.zst" "$dest_ps"
sudo depmod -a

echo ""
echo "==> Phase 8.2 patch $PATCH_ID installed"
echo "Reboot, then one s2idle cycle — see research/phase-8/experiments/0009-falsification-matrix.md"
