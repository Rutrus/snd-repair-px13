#!/usr/bin/env bash
# ASCII timeline diagram from phase6-events.csv (one run).
# Usage: ./scripts/phase6-timeline-diagram.sh RUN_ID [> validation/phase6-runs/run-NNNN/diagram.txt]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
EVENTS="${REPO}/validation/phase6-events.csv"
RUN_ID="${1:?run_id}"
OUT_DIR="${REPO}/validation/phase6-runs/run-${RUN_ID}"

python3 << PY
import csv
from pathlib import Path

events = Path("${EVENTS}")
run_id = "${RUN_ID}"
rows = []
if events.exists():
    with events.open() as f:
        for row in csv.DictReader(f):
            if row["run_id"] == run_id:
                rows.append(row)

if not rows:
    print(f"No events for run {run_id} in {events}")
    print("(Run phase6-events-parse.sh after capture)")
    raise SystemExit(1)

rows.sort(key=lambda r: int(r["offset_ms"]))

# Key milestones per layer (first occurrence)
milestones = []
seen = set()
priority = [
    ("kernel", "PM", "suspend_exit", "PM suspend exit"),
    ("kernel", "rt721", "pm_resume_enter", "RT721 resume enter"),
    ("kernel", "rt721", "pm_wait_start", "RT721 wait init"),
    ("hardware", "rt721", "init_timeout", "rt721 init timeout"),
    ("kernel", "rt721", "pm_wait_ok", "RT721 wait OK"),
    ("kernel", "rt721", "pm_resume_exit", "RT721 resume exit"),
    ("hardware", "rt721", "attached", "RT721 Attached"),
    ("hardware", "rt721", "unattached", "RT721 Unattached"),
    ("kernel", "rt721", "io_init_done", "RT721 io_init done"),
    ("kernel", "rt721", "pm_fail_110", "RT721 PM -110"),
    ("hardware", "tas2783_8", "attached", ":8 Attached"),
    ("hardware", "tas2783_8", "unattached", ":8 Unattached"),
    ("kernel", "tas2783_8", "fw_ready_done", "FW ready :8"),
    ("kernel", "tas2783_8", "playback_without_fw", "playback without fw"),
    ("kernel", "pcm", "hw_params", "PCM hw_params"),
    ("kernel", "pcm", "trigger", "PCM trigger"),
    ("userspace", "px13", None, "px13"),
    ("userspace", "pipewire", None, "PipeWire"),
]

for layer, comp, ev, label in priority:
    for r in rows:
        key = (layer, comp, ev or r["event"])
        if r["layer"] != layer or r["component"] != comp:
            continue
        if ev and r["event"] != ev:
            continue
        if key in seen:
            continue
        seen.add(key)
        milestones.append((int(r["offset_ms"]), label, layer))
        break

print(f"=== Phase 6 timeline diagram — run {run_id} ===")
print("resume (anchor 0 ms)")
print(" │")
for ms, label, layer in sorted(milestones, key=lambda x: x[0]):
    bar = "─" * max(1, min(20, ms // 500))
    print(f" ├{bar} +{ms:5d} ms  [{layer:10}] {label}")
print(" │")
print(" └──── end of captured events")
print()
print(f"Total events: {len(rows)}  (full log: validation/phase6-events.csv)")
PY

if [[ -d "$OUT_DIR" ]]; then
	:
fi
