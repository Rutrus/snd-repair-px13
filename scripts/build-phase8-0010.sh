#!/usr/bin/env bash
# Build/install Phase 8.3 observation 0010: PCI INTx status at STAT1 events.
#
# Stack: Phase 6 trace + 0007 pci-ps + 0008 boundary + 0006b intr_decode + 0010 pci_intx.
# Does NOT run build-phase8.sh (avoids upstream tree reset). Strips Phase 9 falsification only.
#
# Usage:
#   ./scripts/build-phase8-0010.sh
#   ./scripts/phase7-sweep-pre.sh 50 && sudo reboot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
PATCH_0006B="$REPO_ROOT/research/phase-7/proposed/0006b-stat-decode.patch"
PATCH_0007="$REPO_ROOT/research/phase-7/proposed/0007-irq-delivery-trace.patch"
PATCH_0008="$REPO_ROOT/research/phase-8/proposed/0008-irq-boundary-trace.patch"
STAMP="$SRC/.snd-repair-phase8-0010"

phase7_0006b_present() {
	grep -q 'snd_repair_phase7_intr_decode(dev, amd_manager, bus, "post_delay")' \
		"$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
}

phase7_irq_delivery_present() {
	grep -q 'PHASE7 ctx=acp fn=irq_handler_enter' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null
}

phase8_boundary_present() {
	grep -q 'PHASE8 ctx=acp fn=irq_stats' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null
}

phase10_present() {
	grep -q 'fn=pci_intx' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null &&
		grep -q 'fn=pci_intx' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
}

apply_patch() {
	local patch="$1" label="$2"
	echo "==> Applying $label"
	patch -p1 --forward -d "$SRC" <"$patch"
}

echo "==> Strip Phase 9 falsification (keep 7/8/10 observation)"
"$SCRIPT_DIR/restore-ps-falsify.sh"

cd "$SRC"

if ! phase7_irq_delivery_present; then
	apply_patch "$PATCH_0007" "0007 irq-delivery-trace"
fi
if ! phase8_boundary_present; then
	apply_patch "$PATCH_0008" "0008 irq-boundary-trace"
fi
if ! phase7_0006b_present; then
	apply_patch "$PATCH_0006B" "0006b stat-decode"
fi

if ! phase10_present; then
	echo "ERROR: 0010 pci_intx hooks missing in pci-ps.c and amd_manager.c" >&2
	echo "  Re-apply 0010 edits to linux-source tree (see research/phase-8/experiments/0010-pci-intx-observe.md)" >&2
	exit 1
fi

# Guard against duplicate 0007 apply (patch half-merge)
if [[ "$(grep -c 'snd_repair_phase7_acp_resume_id(void)' "$SRC/sound/soc/amd/ps/pci-ps.c")" -gt 1 ]]; then
	echo "ERROR: pci-ps.c has duplicate phase7 blocks — fix tree before rebuild" >&2
	exit 1
fi

echo "phase8-0010-pci-intx" >"$STAMP"
date -Is >>"$STAMP"

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
echo "==> Rebuilding soundwire-amd + snd-pci-ps (forced)"
rm -f "$SRC/drivers/soundwire/amd_manager.o" "$SRC/sound/soc/amd/ps/pci-ps.o"
make -C "$BUILD" M="$(pwd)/drivers/soundwire" CONFIG_SOUNDWIRE=m CONFIG_SOUNDWIRE_AMD=m modules
kernel_make_pci_ps_modules

ko_sw="$SRC/drivers/soundwire/soundwire-amd.ko"
ko_ps="$SRC/sound/soc/amd/ps/snd-pci-ps.ko"
[[ -f "$ko_sw" && -f "$ko_ps" ]] || { echo "Missing .ko" >&2; exit 1; }

verify_ko_phase10() {
	local ko="$1" label="$2"
	if grep -Faq 'fn=pci_intx' "$ko" 2>/dev/null; then
		echo "OK: $label — fn=pci_intx present"
		return 0
	fi
	if strings "$ko" 2>/dev/null | grep -Faq 'fn=pci_intx'; then
		echo "OK: $label — fn=pci_intx present (via strings)"
		return 0
	fi
	echo "ERROR: fn=pci_intx missing in $label ($ko)" >&2
	echo "  Source pci-ps: $(grep -c 'fn=pci_intx' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null || echo 0) hit(s)" >&2
	echo "  Source amd_manager: $(grep -c 'fn=pci_intx' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null || echo 0) hit(s)" >&2
	echo "  If a prior build-phase8 run reset sound/soc, re-run this script (0010 hooks must be in source)." >&2
	return 1
}

verify_ko_phase10 "$ko_ps" "snd-pci-ps.ko"
verify_ko_phase10 "$ko_sw" "soundwire-amd.ko"

zstd -19 -f "$ko_sw" -o "/tmp/soundwire-amd.ko.zst"
zstd -19 -f "$ko_ps" -o "/tmp/snd-pci-ps.ko.zst"
echo "==> Installing modules (requires sudo)"
sudo cp "/tmp/soundwire-amd.ko.zst" "/lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst"
sudo cp "/tmp/snd-pci-ps.ko.zst" "/lib/modules/$KVER/kernel/sound/soc/amd/ps/snd-pci-ps.ko.zst"
sudo depmod -a

echo ""
echo "==> Phase 8.3 / 0010 installed"
echo "  ${SCRIPT_DIR}/phase7-sweep-pre.sh 50"
echo "  sudo reboot"
echo "  ${SCRIPT_DIR}/phase8-irq-snapshot.sh pre-suspend"
echo "  systemctl suspend"
echo "  ${SCRIPT_DIR}/phase8-irq-snapshot.sh post-resume"
echo "  journalctl -k -b 0 | grep -E 'PHASE10.*pci_intx|intr_decode when=post_delay'"
