#!/usr/bin/env bash
# Build/install kernel modules for Q3 SoundWire re-attach investigation.
#
# Installs:
#   - soundwire bus PHASE6 trace (0002)
#   - soundwire-amd PHASE6 trace (0003 + optional 0004–0007 per build-phase6-amd-trace.sh)
#   - snd-soc-tas2783-sdw Q2 trace (TAS2783Q2)
#
# Usage: ./scripts/build-q3-trace.sh
# Then:  sudo reboot
#        systemctl suspend
#        ./scripts/q3-sdw-reattach-collect.sh --label after-resume
#        ./scripts/q3-sdw-reattach-analyze.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Q3 trace build: PHASE6 SDW bus"
"$SCRIPT_DIR/build-phase6-sdw-trace.sh"

echo ""
echo "==> Q3 trace build: PHASE6 AMD manager"
"$SCRIPT_DIR/build-phase6-amd-trace.sh"

echo ""
echo "==> Q3 trace build: TAS2783Q2 (series B + trace)"
"$SCRIPT_DIR/build-q2-fw-trace.sh"

echo ""
echo "==> Q3 modules installed. Reboot required."
echo "After S2:"
echo "  $SCRIPT_DIR/q3-sdw-reattach-collect.sh --label after-resume"
echo "  $SCRIPT_DIR/q3-sdw-reattach-analyze.sh"
echo "Docs: research/q2.5-sdw-reattach/README.md"
