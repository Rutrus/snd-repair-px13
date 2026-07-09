#!/usr/bin/env bash
# Find first divergence between two Phase 6 chronology runs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHRONO="${REPO}/validation/phase6-chronology.csv"
KMSG="${REPO}/validation/phase6-kmsg-events.csv"
RUN_A="${1:?run A}"; RUN_B="${2:?run B}"

echo "=== Phase 6 chronology diff: ${RUN_A} vs ${RUN_B} ==="
echo ""

if [[ ! -f "$CHRONO" ]]; then
	echo "Missing ${CHRONO}" >&2
	exit 1
fi

python3 << PY
import csv
from pathlib import Path

chrono = Path("${CHRONO}")
run_a, run_b = "${RUN_A}", "${RUN_B}"

def rows_for(rid):
    with chrono.open() as f:
        return [row for row in csv.DictReader(f) if row["run_id"] == rid]

a, b = rows_for(run_a), rows_for(run_b)
if not a or not b:
    print(f"Missing samples for {run_a} or {run_b}")
    raise SystemExit(1)

keys = ["uid8_attach", "uid8_fw", "pm", "default_sink", "speaker_present", "composite", "pipewire"]
print("--- Userspace/sysfs timeline (first differing sample) ---")
by_off_a = {float(r["offset_s"]): r for r in a}
by_off_b = {float(r["offset_s"]): r for r in b}
offs = sorted(set(by_off_a) | set(by_off_b))
first = None
for off in offs:
    ra, rb = by_off_a.get(off), by_off_b.get(off)
    if not ra or not rb:
        continue
    diffs = [k for k in keys if ra.get(k) != rb.get(k)]
    if diffs:
        first = (off, diffs, ra, rb)
        break
if first:
    off, diffs, ra, rb = first
    print(f"First sample divergence at t={off}s ({int(float(off)*1000)}ms): fields {diffs}")
    for k in diffs:
        print(f"  {k}: {run_a}={ra[k]}  {run_b}={rb[k]}")
else:
    print("No divergence in sampled fields (same composite path?)")

print()
print("--- Kernel events (first event type in one run only, by offset bucket) ---")
kmsg = Path("${KMSG}")
if kmsg.exists():
    from collections import defaultdict
    def ev_map(rid):
        m = defaultdict(set)
        with kmsg.open() as f:
            for row in csv.DictReader(f):
                if row["run_id"] != rid:
                    continue
                bucket = int(int(row["offset_ms"]) / 500) * 500
                m[bucket].add((row["component"], row["event"]))
        return m
    ea, eb = ev_map(run_a), ev_map(run_b)
    all_b = sorted(set(ea) | set(eb))
    for bucket in all_b:
        only_a = ea.get(bucket, set()) - eb.get(bucket, set())
        only_b = eb.get(bucket, set()) - ea.get(bucket, set())
        if only_a or only_b:
            print(f"  @{bucket}ms: only_{run_a}={only_a or '-'}  only_{run_b}={only_b or '-'}")
            break
    else:
        print("  (no unique kmsg event buckets — compare full phase6-kmsg-events.csv)")
PY

echo ""
echo "Full artifacts:"
echo "  ${CHRONO}"
echo "  ${KMSG}"
echo "  validation/phase6-runs/run-${RUN_A}/"
echo "  validation/phase6-runs/run-${RUN_B}/"
