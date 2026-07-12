#!/usr/bin/env bash
# Q3 — mark observed/missing re-attach ladder transitions from a collect log.
#
# Usage: ./scripts/q3-sdw-reattach-analyze.sh [collect.log]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOG="${1:-}"
if [[ -z "$LOG" ]]; then
	LOG="$(ls -t "$REPO_ROOT"/validation/q3-sdw-reattach/*.log 2>/dev/null | head -1 || true)"
fi
[[ -n "$LOG" && -f "$LOG" ]] || {
	echo "Usage: $0 [validation/q3-sdw-reattach/<file>.log]" >&2
	exit 1
}

python3 - "$LOG" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()

def seen(pattern: str) -> bool:
    return bool(re.search(pattern, text, re.MULTILINE | re.IGNORECASE))

# Ladder ordered for Q3 — first [MISSING] after last [OK] is the break hint.
ladder = [
    ("PM resume exit", r"PM: suspend exit"),
    ("manager_reset (suspend/detach)", r"manager_reset|reason=manager_reset"),
    ("AMD resume / ping / queue_work", r"PHASE6 ctx=amd fn=(resume_enter|ping_status|queue_work|handle_status)"),
    ("SDW state_change UNATTACHED→ATTACHED", r"state_change.*new=ATTACHED|old=ALERT new=ATTACHED|from_alert"),
    ("SDW completion (init_complete signal)", r"fn=completion|initialization_complete"),
    ("Slave ATTACHED (TAS2783Q2 status=1)", r"TAS2783Q2 fn=update_status uid=0x[89ab] status=1"),
    ("call_io_init / io_init enter", r"TAS2783Q2 fn=(call_io_init|io_init enter)"),
    ("request_firmware_nowait", r"TAS2783Q2 fn=io_init nowait"),
    ("fw_ready", r"TAS2783Q2 fn=fw_ready enter"),
]

print(f"=== Q3 ladder analysis ===")
print(f"log: {sys.argv[1]}")
print()

first_missing = None
last_ok = None
for name, pat in ladder:
    ok = seen(pat)
    tag = "OK" if ok else "MISSING"
    print(f"  [{tag:7}] {name}")
    if ok:
        last_ok = name
    elif first_missing is None:
        first_missing = name

print()
if seen(r"initialization timed out|error -110"):
    print("Observed: initialization_complete timeout (-110)")
if seen(r"master_port OK|slave_port OK"):
    print("Observed: bus/master port programming OK (link may be alive)")
if seen(r"skip_io_init|TAS2783Q2 fn=update_status skip"):
    print("Observed: skip_io_init path (status != ATTACHED or hw_init gate)")
if seen(r"fw download wait timeout|playback without fw"):
    print("Observed: hw_params FW wait timeout (downstream of missing attach)")

print()
if first_missing:
    print(f"First missing transition (hint): {first_missing}")
    if last_ok:
        print(f"Last observed transition:      {last_ok}")
    print()
    print("→ Localize with PHASE6 patches on functions after last OK.")
else:
    print("All ladder markers present in log (or log spans full success path).")
PY
