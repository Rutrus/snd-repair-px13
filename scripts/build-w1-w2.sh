#!/usr/bin/env bash
# Branch A trial: W1 (0006a AMD worker) + W2 (TAS2783 forced FW reinit).
#
# Goal: PCM2 plays after systemctl suspend → resume. Not more IRQ theory.
#
# Usage:
#   sudo ./scripts/build-w1-w2.sh
#   sudo ./scripts/build-w1-w2.sh --trace   # W2 + TAS2783Q2 probes
#   sudo reboot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TRACE_ARGS=()
while [[ $# -gt 0 ]]; do
	case "$1" in
	--trace) TRACE_ARGS=(--trace); shift ;;
	-h|--help)
		cat <<EOF
Usage: $0 [--trace]

Builds and installs:
  W1 — soundwire-amd with Phase 7 0006a (manual_irq_schedule on STAT&mask)
  W2 — snd-soc-tas2783-sdw with upstream series B + force-fw-reinit hack

After reboot:
  systemctl suspend && sleep 5
  speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1
  journalctl -k -b 0 | grep -E 'W2 ctx=tas|manual_irq_schedule|ATTACHED|fw_ready'

Docs: research/MAKE-IT-WORK.md
EOF
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

echo "========================================"
echo " Branch A — W1 + W2 (make it work)"
echo "========================================"

echo ""
echo "==> W1: Phase 7 0006a on soundwire-amd"
PHASE6_SKIP_BUILD=1 "$SCRIPT_DIR/build-phase7.sh" --experiment validate-manager-mask

echo ""
echo "==> W2: TAS2783 forced FW reinit"
"$SCRIPT_DIR/build-w2-force-fw.sh" "${TRACE_ARGS[@]}"

echo ""
echo "==> Done. Reboot required, then S2 + speaker-test on hw:1,2."
