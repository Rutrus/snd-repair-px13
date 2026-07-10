#!/usr/bin/env bash
# First diverging event between two runs (ms-ordered, all layers).
# RT721 / init_timeout milestones are prioritized over downstream TAS2783 noise.
#
# Usage: ./scripts/phase6-first-divergence.sh RUN_PASS RUN_FAIL
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
EVENTS="${REPO}/validation/phase6-events.csv"
RUN_A="${1:?run A (e.g. PASS candidate)}"
RUN_B="${2:?run B (e.g. FAIL candidate)}"

python3 << PY
import csv
from pathlib import Path

path = Path("${EVENTS}")
if not path.exists():
    print("Missing phase6-events.csv — run capture + phase6-events-parse first")
    raise SystemExit(1)

# Lower = higher priority when searching for root cause
PRIORITY = {
    ("hardware", "rt721", "init_timeout"): 0,
    ("kernel", "rt721", "pm_fail_110"): 1,
    ("kernel", "sdw_core", "completion"): 2,
    ("kernel", "sdw_core", "state_skip"): 3,
    ("hardware", "sdw_core", "state_change"): 4,
    ("kernel", "rt721", "pm_wait_start"): 8,
    ("kernel", "rt721", "pm_resume_enter"): 10,
    ("hardware", "rt721", "unattached"): 11,
    ("hardware", "rt721", "attached"): 12,
    ("kernel", "rt721", "pm_wait_ok"): 13,
    ("kernel", "rt721", "io_init_enter"): 14,
    ("kernel", "rt721", "io_init_done"): 15,
    ("kernel", "rt721", "pm_resume_exit"): 16,
    ("hardware", "tas2783_8", "unattached"): 20,
    ("hardware", "tas2783_8", "attached"): 21,
}

def load(rid):
    with path.open() as f:
        return sorted(
            [r for r in csv.DictReader(f) if r["run_id"] == rid],
            key=lambda r: (int(r["offset_ms"]), r["layer"], r["component"], r["event"]),
        )

def sig(r):
    return (r["layer"], r["component"], r["event"])

def pri(r):
    return PRIORITY.get(sig(r), 50)

a, b = load("${RUN_A}"), load("${RUN_B}")
if not a or not b:
    print(f"Need events for both ${RUN_A} and ${RUN_B}")
    raise SystemExit(1)

# Milestones present in one run only (early RT721 failures)
set_a = {sig(r) for r in a}
set_b = {sig(r) for r in b}
only_a = set_a - set_b
only_b = set_b - set_a
if only_a or only_b:
    candidates = []
    for r in a:
        if sig(r) in only_a:
            candidates.append(("A-only", r))
    for r in b:
        if sig(r) in only_b:
            candidates.append(("B-only", r))
    candidates.sort(key=lambda x: (pri(x[1]), int(x[1]["offset_ms"])))
    side, row = candidates[0]
    print("=== First divergence (Phase 6) — milestone present in one run only ===")
    print(f"  Run A: ${RUN_A}  Run B: ${RUN_B}")
    print()
    print(f"  {side}: +{row['offset_ms']}ms [{row['layer']}] {row['component']}/{row['event']}")
    print(f"  detail: {row.get('detail', '')[:120]}")
    print()
    print("→ RT721 / attach milestones prioritized; compare PHASE6 t=+…ms in dmesg.")
    print()
    print("Diagrams:")
    print(f"  ./scripts/phase6-timeline-diagram.sh ${RUN_A}")
    print(f"  ./scripts/phase6-timeline-diagram.sh ${RUN_B}")
    raise SystemExit(0)

# Compare event-by-event in offset order (merge walk)
ia = ib = 0
first = None
while ia < len(a) and ib < len(b):
    ma, mb = a[ia], b[ib]
    sa = (int(ma["offset_ms"]), ma["layer"], ma["component"], ma["event"])
    sb = (int(mb["offset_ms"]), mb["layer"], mb["component"], mb["event"])
    if sa[1:] == sb[1:] and abs(sa[0] - sb[0]) <= 50:
        ia += 1
        ib += 1
        continue
    if sa[1:] == sb[1:] and abs(sa[0] - sb[0]) > 50:
        first = ("timing", sa, sb, ma, mb)
        break
    if sa[0] <= sb[0]:
        first = ("event", sa, sb, ma, None)
        break
    first = ("event", sb, sa, mb, None)
    break

print("=== First divergence (Phase 6) ===")
print(f"  Run A: ${RUN_A}  Run B: ${RUN_B}")
print()

if not first:
    if len(a) != len(b):
        first = ("length", None, None, a[min(len(a), len(b)) - 1], b[min(len(a), len(b)) - 1])
    else:
        print("No divergence in parsed event sequence (same milestones?)")
        print("Check raw trace: journalctl -k -b 0 | grep 'PHASE6 ctx='")
        raise SystemExit(0)

kind = first[0]
if kind == "timing":
    _, sa, sb, ma, mb = first
    print(f"First TIMING divergence (>50ms) at same milestone:")
    print(f"  {sa[1]}/{sa[2]}/{sa[3]}  A=+{sa[0]}ms  B=+{sb[0]}ms  Δ={sb[0]-sa[0]}ms")
    if sa[2] == "rt721" or sb[2] == "rt721":
        print("  → RT721 latency delta — inspect PHASE6 fn=resume_exit / wait_init_* t=+…ms")
elif kind == "event":
    _, sa, sb, m_only, _ = first
    print(f"First EVENT divergence near +{min(sa[0], sb[0])}ms:")
    print(f"  A (${RUN_A}): +{sa[0]}ms [{sa[1]}] {sa[2]}/{sa[3]}")
    print(f"  B (${RUN_B}): +{sb[0]}ms [{sb[1]}] {sb[2]}/{sb[3]}")
    print()
    if "rt721" in (sa[2], sb[2]):
        print("→ RT721 milestone — compare PHASE6 kernel trace before TAS2783 downstream.")
    else:
        print("→ Investigate here; later events may be consequences only.")
else:
    print("Runs differ in event count — compare diagrams:")
    print(f"  ./scripts/phase6-timeline-diagram.sh ${RUN_A}")
    print(f"  ./scripts/phase6-timeline-diagram.sh ${RUN_B}")

print()
print("Diagrams:")
print(f"  ./scripts/phase6-timeline-diagram.sh ${RUN_A}")
print(f"  ./scripts/phase6-timeline-diagram.sh ${RUN_B}")
PY
