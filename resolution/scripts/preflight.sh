#!/usr/bin/env bash
# PX13 resolution preflight — run before first E09 cycle.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${_SCRIPT_DIR}/../.." && pwd)}"
LIB="${REPO}/resolution/scripts/recovery/_lib.sh"
# shellcheck source=/dev/null
source "$LIB"

ok=0 fail=0

check() {
	local name="$1" rc="$2"
	if [[ "$rc" -eq 0 ]]; then
		echo "  OK   $name"
		ok=$((ok + 1))
	else
		echo "  FAIL $name"
		fail=$((fail + 1))
	fi
}

echo "=== RESOLUTION PREFLIGHT ==="
echo "PCI: $PCI_DEV"

[[ -d "$(pci_sysfs)" ]] && rc=0 || rc=1
check "ACP PCI sysfs" "$rc"

[[ -r "$(pci_sysfs)/power/control" ]] && rc=0 || rc=1
check "runtime PM sysfs" "$rc"
echo "       control=$(cat "$(pci_sysfs)/power/control" 2>/dev/null) status=$(cat "$(pci_sysfs)/power/runtime_status" 2>/dev/null)"

grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && rc=0 || rc=1
check "ALSA amd-soundwire card" "$rc"

discover_manager_plat >/dev/null && rc=0 || rc=1
check "platform manager $(discover_manager_plat 2>/dev/null || echo ?)" "$rc"

discover_rt721_dev >/dev/null && rc=0 || rc=1
check "RT721 $(discover_rt721_dev 2>/dev/null || echo ?)" "$rc"

[[ -d "$PCI_DRV" ]] && rc=0 || rc=1
check "snd_pci_ps driver" "$rc"

if witness_playback; then
	rc=0
else
	rc=1
fi
check "playback $(alsa_speaker_dev 2>/dev/null || echo plughw:?)" "$rc"

[[ -x "${REPO}/resolution/scripts/recovery/run-recovery.sh" ]] && rc=0 || rc=1
check "run-recovery.sh" "$rc"

echo "---"
echo "Summary: $ok OK, $fail FAIL"
echo ""
if [[ "$fail" -eq 0 ]]; then
	echo "Ready for E09 cycle:"
	echo "  sudo EDGE_FULL_SIGNATURE=1 ${REPO}/resolution/scripts/edge-cycle.sh E09"
else
	echo "Fix FAIL items before edge cycle."
	exit 1
fi
