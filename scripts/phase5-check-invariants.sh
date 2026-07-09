#!/usr/bin/env bash
# Quick invariant check from current boot journal + wpctl (T07).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

kmsg() { journalctl -k -b 0 --no-pager 2>/dev/null || true; }

echo "=== Phase 5 invariants ==="

if kmsg | grep -q 'playback without fw.*uid=0x8.*done=0'; then
	echo "I2: :8 done=0 present"
	uid8_done=0
else
	echo "I2: no :8 done=0 in kmsg"
	uid8_done=1
fi

if XDG_RUNTIME_DIR="/run/user/$(id -u)" wpctl status 2>/dev/null | grep -qi 'Dummy Output'; then
	echo "I1: Dummy Output active"
	dummy=1
else
	echo "I1: no Dummy (or wpctl unavailable)"
	dummy=0
fi

if [[ "$dummy" -eq 1 && "$uid8_done" -eq 0 ]]; then
	echo "I1+I2: consistent (Dummy + :8 broken)"
else
	echo "I1+I2: check manually"
fi

if kmsg | grep -q 'failed to resume: error -110.*01:8'; then
	echo "I4: PM -110 on :8 this boot"
else
	echo "I4: no PM -110 on :8"
fi

echo "See research/phase-5/tracks/T07-invariants.md"
