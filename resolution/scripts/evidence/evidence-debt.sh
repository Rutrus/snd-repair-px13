#!/usr/bin/env bash
# Print evidence debt from hypotheses.yaml (investigation priority).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
HYP="${REPO}/resolution/evidence/hypotheses.yaml"

[[ -f "$HYP" ]] || {
	echo "missing $HYP" >&2
	exit 1
}

python3 - "$HYP" <<'PY'
import sys

try:
    import yaml
except ImportError:
    print("PyYAML not installed — showing raw path:", sys.argv[1])
    sys.exit(0)

path = sys.argv[1]
with open(path) as f:
    data = yaml.safe_load(f)

order = {"high": 0, "medium": 1, "low": 2}

def debt_block(label, items, show_falsified=False):
    rows = []
    for hid, h in sorted(items.items(), key=lambda x: x[0]):
        if not show_falsified and label == "falsified":
            continue
        conf = h.get("confidence", "?")
        debt = h.get("evidence_debt", {})
        score = debt.get("score", "—")
        missing = debt.get("missing", [])
        if label == "falsified":
            score = "closed"
            missing = h.get("falsified_by", [])
        rows.append((order.get(score, 9), hid, h.get("name", ""), conf, score, missing))
    rows.sort(key=lambda r: (r[0], -float(r[3]) if isinstance(r[3], (int, float)) else 0))
    return rows

print("=== Evidence debt ===")
print(f"Source: {path}\n")

for hid, h in data.get("hypotheses", {}).items():
    debt = h.get("evidence_debt", {})
    score = debt.get("score", "—")
    missing = debt.get("missing", [])
    print(f"{hid:16} conf={h.get('confidence', '?'):<5} debt={score}")
    print(f"  depends: {', '.join(h.get('depends', []))}")
    if missing:
        for m in missing:
            print(f"  missing: {m}")
    print()

print("--- Falsified ---")
for hid, h in data.get("falsified", {}).items():
    print(f"{hid:16} conf={h.get('confidence', '?')}  by={h.get('falsified_by', [])}")

summary_path = path.replace("hypotheses.yaml", "confidence.yaml")
try:
    with open(summary_path) as f:
        conf = yaml.safe_load(f)
    order = conf.get("evidence_debt_summary", {}).get("order", [])
    if order:
        print("\n--- Suggested next (confidence.yaml) ---")
        for item in order:
            print(f"  {item['id']:12} debt={item['debt']}  actions={item.get('next_actions', [])}")
except FileNotFoundError:
    pass
PY
