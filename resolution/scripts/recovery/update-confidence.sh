#!/usr/bin/env bash
# Update edges/state.json confidence. Usage: update-confidence.sh E09 full|partial|fail
set -euo pipefail

EDGE="${1:-}"
OUTCOME="${2:-}"
REPO="${SND_REPAIR_REPO:-${HOME}/snd_repair}"
STATE="${REPO}/resolution/edges/state.json"

[[ -f "$STATE" ]] || { echo "missing $STATE" >&2; exit 1; }

python3 - "$EDGE" "$OUTCOME" "$STATE" <<'PY'
import json, sys
edge, outcome, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
e = data["edges"].get(edge)
if not e:
    print(f"unknown edge {edge}", file=sys.stderr)
    sys.exit(1)

sat = data.get("saturation_threshold", 3)
mx = e.get("max_confidence", 5)

if outcome == "full":
    e["confidence"] = min(mx, e["confidence"] + 1)
    e["consecutive_zero_knowledge"] = 0
    if e["confidence"] == 1:
        e["status"] = "pass_x1"
    elif e["confidence"] < mx:
        e["status"] = "reproducible"
    else:
        e["status"] = "stable"
elif outcome == "partial":
    e["consecutive_zero_knowledge"] = 0
    if e["confidence"] == 0:
        e["status"] = "pass_x1"
else:  # fail
    e["confidence"] = 0
    e["status"] = "hypothesis"
    e["consecutive_zero_knowledge"] = e.get("consecutive_zero_knowledge", 0) + 1
    if e["consecutive_zero_knowledge"] >= sat:
        e["branch_saturated"] = True

data["active_edge"] = edge
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"{edge}: confidence={e['confidence']}/{mx} status={e['status']} zero_k={e['consecutive_zero_knowledge']}")
PY
