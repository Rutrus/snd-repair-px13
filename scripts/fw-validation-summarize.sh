#!/usr/bin/env bash
# Genera validation/fw-summary.md desde fw-matrix.csv
# Uso: fw-validation-summarize.sh [validation/]

set -euo pipefail

VAL_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/validation}"
CSV="${VAL_DIR}/fw-matrix.csv"
SUMMARY="${VAL_DIR}/fw-summary.md"

if [[ ! -f "$CSV" ]]; then
	echo "No existe ${CSV} — ejecuta fw-validation-collect.sh primero" >&2
	exit 1
fi

python3 - "$CSV" "$SUMMARY" <<'PY'
import csv
import sys
from collections import Counter, defaultdict
from datetime import datetime

csv_path, out_path = sys.argv[1:3]

rows = []
with open(csv_path, newline="") as f:
    for row in csv.DictReader(f):
        rows.append(row)

n = len(rows)
if n == 0:
    with open(out_path, "w") as f:
        f.write("# FW validation summary\n\nSin entradas en CSV.\n")
    sys.exit(0)

def norm_ok(v):
    return v == "OK"

def norm_fail(v):
    return v.startswith("FAIL")

def pct(num, den):
    return f"{100.0 * num / den:.1f}%" if den else "n/a"

uid8 = Counter(r["uid8_fw"] for r in rows)
uidb = Counter(r["uidb_fw"] for r in rows)

uid8_ok = sum(1 for r in rows if norm_ok(r["uid8_fw"]))
uidb_ok = sum(1 for r in rows if norm_ok(r["uidb_fw"]))
both_ok = sum(1 for r in rows if norm_ok(r["uid8_fw"]) and norm_ok(r["uidb_fw"]))

regress = sum(1 for r in rows if r.get("regression_capture", "").upper() == "YES")

# Audio (solo filas con datos)
audio_rows = [r for r in rows if r.get("left_audio") or r.get("right_audio")]
lr_ok = sum(1 for r in audio_rows if r.get("left_audio") == "1" and r.get("right_audio") == "1")

# Por contexto
by_ctx = defaultdict(list)
for r in rows:
    by_ctx[r.get("suspend_resume", "boot")].append(r)

by_rate = defaultdict(list)
for r in rows:
    by_rate[r.get("rate", "") or "unknown"].append(r)

kernels = Counter(r.get("kernel", "?") for r in rows)

lines = []
lines.append("# FW validation summary")
lines.append("")
lines.append(f"Generado: {datetime.now().isoformat(timespec='seconds')}")
lines.append(f"Fuente: `{csv_path}`")
lines.append("")
lines.append(f"## Boots analizados: **{n}**")
lines.append("")
lines.append("### Éxito global FW (ambos UIDs OK)")
lines.append("")
lines.append(f"- **{both_ok}/{n}** ({pct(both_ok, n)})")
lines.append("")
lines.append("### UID `:8` (tas2783-1 / Left)")
lines.append("")
for k in sorted(uid8.keys()):
    lines.append(f"- `{k}`: {uid8[k]}")
lines.append("")
lines.append("### UID `:b` (tas2783-2 / Right)")
lines.append("")
for k in sorted(uidb.keys()):
    lines.append(f"- `{k}`: {uidb[k]}")
lines.append("")
lines.append("### Regresión capture (Problema A)")
lines.append("")
lines.append(f"- `REGRESSION_CAPTURE=YES`: **{regress}/{n}**")
lines.append("")
if audio_rows:
    lines.append("### Audio L+R (entradas con --audio)")
    lines.append("")
    lines.append(f"- Ambos canales OK: **{lr_ok}/{len(audio_rows)}** ({pct(lr_ok, len(audio_rows))})")
    lines.append("")
lines.append("### Por contexto (`suspend_resume`)")
lines.append("")
for ctx in sorted(by_ctx.keys()):
    sub = by_ctx[ctx]
    ok = sum(1 for r in sub if norm_ok(r["uid8_fw"]) and norm_ok(r["uidb_fw"]))
    lines.append(f"- **{ctx}**: {ok}/{len(sub)} OK global")
lines.append("")
lines.append("### Por frecuencia (`rate`)")
lines.append("")
for rate in sorted(by_rate.keys(), key=lambda x: (x == "unknown", x)):
    sub = by_rate[rate]
    ok = sum(1 for r in sub if norm_ok(r["uid8_fw"]) and norm_ok(r["uidb_fw"]))
    lines.append(f"- **{rate} Hz**: {ok}/{len(sub)} OK global")
lines.append("")
lines.append("### Kernels")
lines.append("")
for k, c in kernels.most_common():
    lines.append(f"- `{k}`: {c} boots")
lines.append("")
lines.append("## Tabla completa")
lines.append("")
lines.append("| boot | timestamp | :8 | :b | L | R | ctx | rate | regr | notes |")
lines.append("|------|-----------|----|----|---|---|-----|------|------|-------|")
for r in rows:
    lines.append(
        f"| {r['boot_id']} | {r['timestamp'][:16]} | {r['uid8_fw']} | {r['uidb_fw']} | "
        f"{r.get('left_audio','')} | {r.get('right_audio','')} | {r.get('suspend_resume','')} | "
        f"{r.get('rate','')} | {r.get('regression_capture','')} | {r.get('notes','')} |"
    )
lines.append("")
lines.append("## Criterio RFC Serie B (objetivo)")
lines.append("")
lines.append("- 20–30 boots, 0× `FAIL110` en `:b`")
lines.append("- Suspend/resume ≥6/6 OK")
lines.append("- Rates 44100 / 48000 / 96000 sin regresión")
lines.append("- `regression_capture=NO` en todos los boots")
lines.append("")

with open(out_path, "w") as f:
    f.write("\n".join(lines))

print(f"Resumen → {out_path}")
PY
