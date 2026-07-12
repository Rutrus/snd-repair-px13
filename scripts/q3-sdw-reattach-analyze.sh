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

raw = Path(sys.argv[1]).read_text()

# Focus on last resume cycle: from last system_suspend invalidate / manager_reset.
markers = list(re.finditer(
    r"system_suspend invalidate|reason=manager_reset|PM: suspend entry",
    raw,
    re.IGNORECASE,
))
if markers:
    text = raw[markers[-1].start():]
    scope = f"post last suspend marker (offset {markers[-1].start()})"
else:
    text = raw
    scope = "full log (no suspend marker — prefer q3-sdw-reattach-collect.sh)"

def seen(pattern: str) -> bool:
    return bool(re.search(pattern, text, re.MULTILINE | re.IGNORECASE))

# Post-resume ATTACHED must appear after invalidate in this window.
post_attached = seen(
    r"TAS2783Q2 fn=update_status uid=0x[89ab] status=1"
    r"(?!.*system_suspend invalidate)"
)
# Simpler: status=1 after skip with status=0 in same window
has_post_unattached = seen(r"TAS2783Q2 fn=update_status uid=0x[89ab] status=0")
has_post_attached = bool(re.search(
    r"system_suspend invalidate[\s\S]*?"
    r"TAS2783Q2 fn=update_status uid=0x[89ab] status=1",
    text,
    re.MULTILINE,
))

ladder = [
    ("PM suspend exit (resume complete)", r"PM: suspend exit"),
    ("system_suspend invalidate", r"system_suspend invalidate"),
    ("manager_reset / UNATTACHED detach", r"manager_reset|status=0 hw_init=0 success=0"),
    ("AMD resume / ping / queue_work (PHASE6)", r"PHASE6 ctx=amd fn=(resume_enter|ping_status|queue_work|handle_status)"),
    ("init timeout (-110) on slave", r"initialization timed out|failed to resume: error -110"),
    ("SDW ATTACHED transition post-reset (PHASE6)", r"PHASE6 ctx=sdw fn=state_change.*new=ATTACHED|fn=completion"),
    ("TAS2783Q2 status=1 after invalidate", r"system_suspend invalidate[\s\S]{0,8000}TAS2783Q2 fn=update_status uid=0x[89ab] status=1"),
    ("TAS2783Q2 call_io_init after invalidate", r"system_suspend invalidate[\s\S]{0,12000}TAS2783Q2 fn=(call_io_init|io_init enter)"),
    ("TAS2783Q2 nowait after invalidate", r"system_suspend invalidate[\s\S]{0,15000}TAS2783Q2 fn=io_init nowait"),
    ("TAS2783Q2 fw_ready after invalidate", r"system_suspend invalidate[\s\S]{0,20000}TAS2783Q2 fn=fw_ready enter"),
    ("hw_params FW timeout (downstream)", r"fw download wait timeout|TAS2783Q2 fn=hw_params wait"),
]

print(f"=== Q3 ladder analysis ===")
print(f"log: {sys.argv[1]}")
print(f"scope: {scope}")
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
    print("Observed: bus/master port programming OK")
if seen(r"skip_io_init|TAS2783Q2 fn=update_status skip"):
    print("Observed: skip_io_init (expected when status != ATTACHED)")
if seen(r"fw download wait timeout|playback without fw"):
    print("Observed: hw_params FW wait (downstream symptom)")

if has_post_unattached and not has_post_attached:
    print("Observed: post-invalidate status=0 without later status=1 (no re-attach this cycle)")

print()
if first_missing:
    print(f"First missing transition (hint): {first_missing}")
    if last_ok:
        print(f"Last observed transition:      {last_ok}")
    print()
    print("→ Use q3-sdw-reattach-collect.sh (PHASE6+Q2) for reliable ladder.")
else:
    print("All post-suspend ladder markers present.")
PY
