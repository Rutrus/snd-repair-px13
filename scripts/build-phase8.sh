#!/usr/bin/env bash
# Build/install Phase 8 ACP IRQ observation on Phase 6 + 0007 pci-ps base.
#
# Usage:
#   ./scripts/build-phase8.sh --experiment irq-boundary-trace
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
EXPERIMENT="${PHASE8_EXPERIMENT:-irq-boundary-trace}"
STAMP_P8="$SRC/.snd-repair-phase8-experiment"
PATCH_0007="$REPO_ROOT/research/phase-7/proposed/0007-irq-delivery-trace.patch"
PATCH_0008="$REPO_ROOT/research/phase-8/proposed/0008-irq-boundary-trace.patch"

usage() {
	cat <<EOF
Usage: $0 [--experiment irq-boundary-trace]

Phase 8 applies on Phase 6 trace + 0007 pci-ps (observation only).
Does not install 0006b or 0007 correlate unless already in tree.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--experiment) EXPERIMENT="${2:?}"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown: $1" >&2; usage; exit 1 ;;
	esac
done

phase7_irq_delivery_present() {
	grep -q 'PHASE7 ctx=acp fn=irq_handler_enter' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null
}

phase8_boundary_present() {
	grep -q 'PHASE8 ctx=acp fn=irq_stats' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null &&
		grep -q 'PHASE8 ctx=acp fn=pm_suspend_enter' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null
}

apply_pci_patch() {
	local patch="$1" label="$2"
	rm -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej"
	echo "==> Applying Phase 8 (pci-ps): $label"
	if patch -p1 --forward -d "$SRC" <"$patch"; then
		return 0
	fi
	rm -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej"
	return 1
}

echo "==> Phase 6 trace base"
PHASE6_SKIP_BUILD=1 "$SCRIPT_DIR/build-phase6-amd-trace.sh"

cd "$SRC"

if ! phase7_irq_delivery_present; then
	apply_pci_patch "$PATCH_0007" "0007 irq-delivery-trace (base)" || {
		phase7_irq_delivery_present || { echo "ERROR: 0007 base failed" >&2; exit 1; }
	}
fi

if ! phase8_boundary_present; then
	[[ -f "$PATCH_0008" ]] || {
		echo "Missing $PATCH_0008 — run ./scripts/regenerate-phase8-0008.sh" >&2
		exit 1
	}
	apply_pci_patch "$PATCH_0008" "0008 irq-boundary-trace" || {
		phase8_boundary_present || {
			echo "ERROR: 0008 patch failed" >&2
			[[ -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej" ]] && cat "$SRC/sound/soc/amd/ps/pci-ps.c.rej" >&2
			exit 1
		}
	}
fi

[[ -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej" ]] && {
	echo "ERROR: pci-ps .rej left" >&2
	exit 1
}

echo "$EXPERIMENT" >"$STAMP_P8"
date -Is >>"$STAMP_P8"

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
echo "==> Rebuilding snd-pci-ps (Phase 8 $EXPERIMENT)"
kernel_make_pci_ps_modules

ko_ps="sound/soc/amd/ps/snd-pci-ps.ko"
dest_ps="/lib/modules/$KVER/kernel/sound/soc/amd/ps/snd-pci-ps.ko.zst"
[[ -f "$ko_ps" ]] || { echo "Missing $ko_ps" >&2; exit 1; }

if strings "$ko_ps" | grep -q 'PHASE8 ctx=acp fn=irq_stats'; then
	echo "OK: phase8 irq-boundary-trace present"
else
	echo "WARN: PHASE8 strings missing in snd-pci-ps.ko" >&2
fi

name_ps="$(basename "$ko_ps")"
zstd -19 -f "$ko_ps" -o "/tmp/$name_ps.zst"
echo "==> Installing $dest_ps (requires sudo)"
sudo cp "/tmp/$name_ps.zst" "$dest_ps"
sudo depmod -a

echo ""
echo "==> Phase 8 installed: $EXPERIMENT"
echo "Reboot, then:"
echo "  ${SCRIPT_DIR}/phase8-irq-snapshot.sh pre-suspend"
echo "  systemctl suspend"
echo "  ${SCRIPT_DIR}/phase8-irq-snapshot.sh post-resume"
echo "  journalctl -k -b 0 | grep 'PHASE8 ctx=acp fn='"
echo "  ${SCRIPT_DIR}/phase8-irq-snapshot.sh compare"
