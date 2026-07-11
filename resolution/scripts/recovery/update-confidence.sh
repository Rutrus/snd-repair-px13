#!/usr/bin/env bash
# Update edges/state.json — dynamic confidence. Usage: update-confidence.sh E09 full|partial|fail|consolidation
set -euo pipefail

EDGE="${1:-}"
OUTCOME="${2:-}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${_SCRIPT_DIR}/../../.." && pwd)}"
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

th = data.get("confidence_thresholds", {})
sat = data.get("saturation_threshold", 3)
need = data.get("consolidation_runs", 3)

def set_status():
    conf = e.get("confidence", 0.0)
    cc = e.get("consolidation_count", 0)
    if cc >= need and conf >= th.get("stable", 0.95) - 0.01:
        e["status"] = "stable"
    elif conf >= th.get("promising", 0.60):
        e["status"] = "promising"
    else:
        e["status"] = "new"

e["explored"] = True

if outcome == "full":
    e["execution"] = "pass"
    e["consecutive_zero_knowledge"] = 0
    base = 0.60
    if e.get("research_coherent"):
        base = max(base, 0.75)
    if e.get("research_ready"):
        base = max(base, 0.85)
    # first full pass in exploration
    if e.get("confidence", 0) < base:
        e["confidence"] = base
    set_status()

elif outcome == "partial":
    e["consecutive_zero_knowledge"] = 0
    e["confidence"] = max(e.get("confidence", 0), 0.40)
    # stay NEW until full S1-S4

elif outcome == "consolidation":
    e["consecutive_zero_knowledge"] = 0
    e["consolidation_count"] = e.get("consolidation_count", 0) + 1
    e["confidence"] = min(0.95, e.get("confidence", 0.60) + 0.05)
    set_status()

elif outcome in ("blocked", "domain_incomplete"):
    e["consecutive_zero_knowledge"] = 0
    e["execution"] = "blocked"
    e["domain_status"] = "blocked"
    e["confidence"] = max(e.get("confidence", 0), 0.35)
    if e.get("research_coherent"):
        e["confidence"] = max(e["confidence"], 0.40)

else:  # fail
    e["execution"] = "fail"
    e["consecutive_zero_knowledge"] = e.get("consecutive_zero_knowledge", 0) + 1
    if e["consecutive_zero_knowledge"] >= sat:
        e["branch_saturated"] = True
    if e.get("status") == "new":
        # Informative FAIL (valid witness) still yields knowledge
        base = 0.35 if e.get("research_coherent") else 0.0
        e["confidence"] = max(e.get("confidence", 0), base)

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(
    f"{edge}: confidence={e['confidence']:.2f} status={e['status']} "
    f"consolidation={e.get('consolidation_count', 0)}/{need} "
    f"zero_k={e['consecutive_zero_knowledge']}"
)
PY
