#!/usr/bin/env bash
# Compute next edge per exploration-first queue. Usage: next-edge.sh [after EDGE]
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${_SCRIPT_DIR}/../../.." && pwd)}"
STATE="${REPO}/resolution/edges/state.json"
AFTER="${1:-}"

python3 - "$STATE" "$AFTER" <<'PY'
import json, sys

path, after = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)

phase = data.get("phase", "exploration")
queue = data["exploration_queue"]
edges = data["edges"]

def edge_id(eid):
    e = edges.get(eid)
    if not e:
        return None
    if e.get("branch_saturated"):
        return None
    return eid

if phase == "consolidation":
    # highest confidence PROMISING/STABLE candidate needing consolidation
    best = None
    best_conf = -1.0
    need = data.get("consolidation_runs", 3)
    for eid, e in edges.items():
        if e.get("status") not in ("promising", "stable"):
            continue
        cc = e.get("consolidation_count", 0)
        if cc >= need:
            continue
        conf = e.get("confidence", 0)
        if conf > best_conf:
            best_conf = conf
            best = eid
    print(best or "DONE")
    sys.exit(0)

# exploration: walk queue after `after`, else first NEW
start = 0
if after:
    try:
        start = queue.index(after) + 1
    except ValueError:
        start = 0

def unexplored(e):
    if not e or e.get("branch_saturated"):
        return False
    return not e.get("explored", False)

for eid in queue[start:]:
    e = edges.get(eid)
    if unexplored(e):
        print(eid)
        sys.exit(0)

for eid in queue:
    e = edges.get(eid)
    if unexplored(e):
        print(eid)
        sys.exit(0)

# exploration complete → consolidation
promising = [eid for eid, e in edges.items() if e.get("status") == "promising"]
if promising:
    print("CONSOLIDATION")
else:
    print("DONE")
PY
