#!/usr/bin/env bash
# Campaign status: active, converging, parked, killed, succeeded.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CAMP_DIR="${REPO}/resolution/campaigns"

python3 - "$CAMP_DIR" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML required")
    sys.exit(1)

camp_dir = Path(sys.argv[1])
buckets = {"active": [], "converging": [], "parked": [], "killed": [], "succeeded": []}

for d in sorted(camp_dir.iterdir()):
    yf = d / "campaign.yaml"
    if not yf.is_file():
        continue
    with open(yf) as f:
        c = yaml.safe_load(f)
    st = c.get("status", "parked")
    buckets.setdefault(st, []).append(c)

print("=== Campaign status ===")
print(
    f"Active: {len(buckets['active'])} · Converging: {len(buckets['converging'])} · "
    f"Killed: {len(buckets['killed'])} · Parked: {len(buckets.get('parked', []))}\n"
)

for label in ("converging", "active"):
    for c in sorted(buckets.get(label, []), key=lambda x: x.get("priority", 99)):
        phase = c.get("phase", "—")
        print(f"{c['id']:20} [{c.get('status')}] phase={phase}  EIG={c.get('expected_information_gain', '?')}")
        print(f"  goal: {c.get('goal', '').strip()[:90]}...")
        print(f"  weekly: {c.get('weekly_kill_target', '—')}")
        print()

if buckets.get("killed"):
    print("--- Killed ---")
    for c in buckets["killed"]:
        stmt = c.get("kill_statement", "")[:80]
        print(f"  {c['id']:20}  closed={c.get('closed_at', '?')}  {stmt}...")

if buckets.get("parked"):
    print("--- Parked ---")
    for c in buckets["parked"]:
        print(f"  {c['id']:20}")

print("\nLifecycle: ACTIVE → CONVERGING → KILLED | SUCCEEDED")
PY
