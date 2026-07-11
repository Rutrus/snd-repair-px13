#!/usr/bin/env bash
# Edge metadata for structured reports. Usage: edge-metadata.sh R09
set -euo pipefail

RID="${1:-}"
case "$RID" in
R09) EDGE=E09; LAYER=L4; COST=3; KNOW=5; QUESTION="What does runtime PM do that system PM does not?"; NEXT_FAIL=E07 ;;
R07) EDGE=E07; LAYER=L4; COST=4; KNOW=5; QUESTION="What does probe() do that pm_resume() does not?"; NEXT_FAIL=E08 ;;
R08) EDGE=E08; LAYER=L4; COST=5; KNOW=3; QUESTION="What does re-enumeration reset that unbind+bind does not?"; NEXT_FAIL=E04 ;;
R04) EDGE=E04; LAYER=L2; COST=2; KNOW=3; QUESTION="What does manager probe() do that pm_resume() does not?"; NEXT_FAIL=FW01 ;;
R06) EDGE=E06; LAYER=L3; COST=4; KNOW=3; QUESTION="What does module reload restore?"; NEXT_FAIL=E07 ;;
R01) EDGE=E01; LAYER=L0; COST=1; KNOW=1; QUESTION="Userspace only?"; NEXT_FAIL=E02 ;;
R02) EDGE=E02; LAYER=L1; COST=2; KNOW=2; QUESTION="ALSA reopen sufficient?"; NEXT_FAIL=E04 ;;
R10) EDGE=E10; LAYER=L7; COST=3; KNOW=2; QUESTION="Second system suspend clears state?"; NEXT_FAIL=E07 ;;
*) EDGE=UNKNOWN; LAYER=?; COST=?; KNOW=0; QUESTION=""; NEXT_FAIL=E09 ;;
esac

export RESOLUTION_EDGE="$EDGE" RESOLUTION_LAYER="$LAYER" RESOLUTION_COST="$COST"
export RESOLUTION_KNOW="$KNOW" RESOLUTION_QUESTION="$QUESTION" RESOLUTION_NEXT_FAIL="$NEXT_FAIL"
