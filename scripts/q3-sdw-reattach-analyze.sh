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

TS_RE = re.compile(r"^(\w{3} \d+ \d+:\d+:\d+\.\d+)")

def line_ts(line: str) -> str | None:
    m = TS_RE.match(line)
    return m.group(1) if m else None

def filter_after_ts(blob: str, anchor_ts: str) -> str:
    out = []
    for line in blob.splitlines():
        ts = line_ts(line)
        if ts is None or ts >= anchor_ts:
            out.append(line)
    return "\n".join(out)

# Chronological scope: last resume cycle from PM suspend entry, then post manager_reset.
entry_m = list(re.finditer(r"PM: suspend entry", raw))
reset_lines = [
    ln for ln in raw.splitlines()
    if "fn=manager_reset link=" in ln and "resume=1" in ln
]
reset_ts = line_ts(reset_lines[-1]) if reset_lines else None

if entry_m:
    text = raw[entry_m[-1].start():]
    scope = f"post last PM suspend entry (offset {entry_m[-1].start()})"
elif reset_lines:
    text = filter_after_ts(raw, reset_ts)
    scope = f"post manager_reset ts={reset_ts}"
else:
    text = raw
    scope = "full log (no suspend marker — prefer q3-sdw-reattach-collect.sh)"

post_text = filter_after_ts(text, reset_ts) if reset_ts else text
if reset_ts:
    scope += f"; post-reset ts>={reset_ts}"

post_reset = r"fn=manager_reset link=\d+ resume=1"
reset_in_scope = reset_ts is not None

def seen(pattern: str, src: str | None = None) -> bool:
    return bool(re.search(pattern, src or text, re.MULTILINE | re.IGNORECASE))

def seen_post(pattern: str) -> bool:
    return seen(pattern, post_text)

has_post_unattached = bool(re.search(
    r"TAS2783Q2 fn=update_status uid=0x[89ab] status=0",
    post_text,
    re.MULTILINE,
))
has_post_attached = bool(re.search(
    r"TAS2783Q2 fn=update_status uid=0x[89ab] status=1",
    post_text,
    re.MULTILINE,
))

ladder = [
    ("PM suspend entry", r"PM: suspend entry"),
    ("PM suspend exit (resume complete)", r"PM: suspend exit"),
    ("AMD manager resume_enter (resume=1)", r"PHASE6 ctx=amd fn=resume_enter.*resume=1"),
    ("manager_reset → UNATTACHED detach", r"fn=state_change.*new=UNATTACHED.*reason=manager_reset"),
    ("AMD worker path post-reset (not observed if missing)", r"PHASE6 ctx=amd fn=(irq_thread_enter|ping_irq|queue_work|handle_status)"),
    ("SDW ATTACHED re-attach post-reset", r"fn=state_change.*new=ATTACHED|fn=completion"),
    ("slave initialization_complete OK", r"wait_init_done|fn=resume_exit.*ret=0"),
    ("init timeout (-110) on slave", r"initialization timed out|wait_init_timeout|failed to resume: error -110"),
    ("TAS2783Q2 status=1 post-reset", r"TAS2783Q2 fn=update_status uid=0x[89ab] status=1"),
    ("TAS2783Q2 io_init / nowait post-reset", r"TAS2783Q2 fn=(call_io_init|io_init enter|io_init nowait)"),
    ("hw_params FW timeout (downstream)", r"fw download wait timeout|TAS2783Q2 fn=hw_params wait"),
]

# Pre-reset steps use full cycle window; post-reset steps use post_text only.
post_reset_names = {
    "AMD worker path post-reset (not observed if missing)",
    "SDW ATTACHED re-attach post-reset",
    "slave initialization_complete OK",
    "init timeout (-110) on slave",
    "TAS2783Q2 status=1 post-reset",
    "TAS2783Q2 io_init / nowait post-reset",
}

print(f"=== Q3 ladder analysis ===")
print(f"log: {sys.argv[1]}")
print(f"scope: {scope}")
print()

first_missing = None
last_ok = None
for name, pat in ladder:
    ok = seen_post(pat) if name in post_reset_names else seen(pat)
    tag = "OBSERVED" if ok else "NOT_OBS"
    print(f"  [{tag:7}] {name}")
    if first_missing is None:
        if ok:
            last_ok = name
        else:
            first_missing = name

print()
if seen_post(r"initialization timed out|wait_init_timeout|error -110"):
    print("Observed: initialization_complete timeout (-110)")
if seen(r"master_port OK|slave_port OK"):
    print("Observed: bus/master port programming OK (may be pre-failure playback)")
if seen_post(r"skip_io_init|TAS2783Q2 fn=update_status skip"):
    print("Observed: skip_io_init (expected when status != ATTACHED)")
if seen_post(r"fw download wait timeout|playback without fw"):
    print("Observed: hw_params FW wait (downstream symptom)")
if seen_post(r"intr_decode when=post_delay.*STAT1=0x4"):
    print("Observed: STAT1=0x4 after manager_reset delay (register read — not proof of handler run)")

if has_post_unattached and not has_post_attached:
    print("Observed: post-reset status=0 without later status=1 (no re-attach this cycle)")

# Q3.1 four-checkpoint bisect (post manager_reset timestamps only).
q31 = [
    ("C1 ACP irq_handler_enter", r"PHASE7 ctx=acp fn=irq_handler_enter"),
    ("C2 ACP sdw1_irq or HANDLED exit", r"PHASE7 ctx=acp fn=sdw1_irq|irq_handler_exit.*sdw1=1"),
    ("C3 AMD irq_thread_enter", r"PHASE6 ctx=amd fn=irq_thread_enter"),
    ("C4 AMD handle_status", r"PHASE6 ctx=amd fn=handle_status"),
    ("C5 state_change ATTACHED", r"fn=state_change.*new=ATTACHED|fn=completion"),
]
print()
print("=== Q3.1 checkpoints (STAT1=0x4 → ATTACHED) ===")
print("Note: NOT_OBS = not seen in trace — not proof of non-execution until probe covers site.")
print()
first_q31 = None
last_q31 = None
for name, pat in q31:
    ok = seen_post(pat)
    tag = "OBSERVED" if ok else "NOT_OBS"
    print(f"  [{tag:7}] {name}")
    if first_q31 is None:
        if ok:
            last_q31 = name
        else:
            first_q31 = name

if seen(r"PHASE8 ctx=acp fn=irq_stats.*since_pm=0"):
    print()
    print("=== Q3.1 C1 verdict ===")
    print("  [FACT   ] handler_since_pm=0 — acp63_irq_handler not entered since suspend")
    if seen_post(r"intr_decode when=post_delay.*STAT1=0x4"):
        print("  [FACT   ] STAT1=0x4 in manager decode post-reset")
    print("  → C1 closed: delivery gap before/at Linux IRQ handler")
    print("  → Pair with phase8-irq-snapshot compare (delta=0) for upstream cite")
    print("  → Optional: 0006a causal retest for downstream sufficiency")
elif seen(r"PHASE8 ctx=acp fn=irq_stats.*since_pm=[1-9]"):
    print("Observed: PHASE8 handler_since_pm>0 (handler ran since suspend — re-open C1)")

print()
if first_missing:
    print(f"Q3 first not-observed (ladder): {first_missing}")
    if last_ok:
        print(f"Q3 last observed (ladder):     {last_ok}")
if first_q31:
    print(f"Q3.1 first not-observed:       {first_q31}")
    if last_q31:
        print(f"Q3.1 last observed:            {last_q31}")
    print()
    print("→ C1 high-confidence: ./scripts/q3.1-c1-boundary-run.sh (before 0006a)")
    print("→ Docs: research/q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md")
else:
    print("Q3.1: all checkpoints observed in window.")
PY
