#!/usr/bin/env bash
# Phase 7 sweep — BEFORE reboot (one delay value per boot).
#
# Writes modprobe.d so phase7_delay_ms applies at module load (echo does NOT
# survive reboot). Then reboots — process ends here.
#
# Usage:
#   ./scripts/phase7-sweep-pre.sh 20
#   # after login:
#   ./scripts/phase7-sweep-post.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${REPO}/validation/.state"
MODPROBE_D="/etc/modprobe.d/snd-repair-phase7.conf"
VALID_MS=(0 5 10 20 50 100)

MS="${1:-}"
if [[ -z "$MS" ]] || ! [[ "$MS" =~ ^[0-9]+$ ]]; then
	echo "Usage: $0 MS   (sweep: ${VALID_MS[*]})" >&2
	exit 1
fi

ok=0
for v in "${VALID_MS[@]}"; do
	[[ "$v" -eq "$MS" ]] && ok=1
done
[[ "$ok" -eq 1 ]] || {
	echo "WARN: MS=$MS not in standard sweep set ${VALID_MS[*]}" >&2
}

mkdir -p "$STATE_DIR"
echo "$MS" >"${STATE_DIR}/phase7-sweep-ms"

sudo tee "$MODPROBE_D" >/dev/null <<EOF
# snd-repair phase7 experiment 0005 — falsification, NOT a fix
# Remove this file when sweep is complete: sudo rm $MODPROBE_D
options soundwire_amd phase7_delay_ms=${MS}
EOF

echo "=== Phase 7 sweep PRE (delay_ms=${MS}) ==="
echo "  modprobe.d: ${MODPROBE_D}"
echo "  state:      ${STATE_DIR}/phase7-sweep-ms"
echo ""
echo "After login, FIRST verify param persisted:"
echo "  ${SCRIPT_DIR}/phase7-sweep-post.sh --verify-only"
echo ""
echo "Then run full post-boot step:"
echo "  ${SCRIPT_DIR}/phase7-sweep-post.sh"
echo ""
echo "Rebooting in 3s (Ctrl+C to cancel)..."
sleep 3
sudo reboot
