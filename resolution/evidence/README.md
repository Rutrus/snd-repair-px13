# Evidence — causal model

English (canonical). **Facts ≠ invariants ≠ hypotheses.**

| File | Role |
|------|------|
| [accepted_models.yaml](accepted_models.yaml) | M_INTX_CORE — **observation vs inference** |
| [assumptions.yaml](assumptions.yaml) | Implicit assumptions (maintainer may challenge) |
| [invariants.yaml](invariants.yaml) | Stable measurements I001… |
| [facts.yaml](facts.yaml) | Volatile F004, F012… |
| [hypotheses.yaml](hypotheses.yaml) | H_INTX_CAUSE, competitors |
| [confidence.yaml](confidence.yaml) | Edges between I/F nodes |
| [graph.md](graph.md) | Fact-only view |

Negative: [../negative/rejected-fixes.yaml](../negative/rejected-fixes.yaml)

---

## Fundamental unit

> **The fundamental unit of the project is no longer an experiment; it is a change of confidence in a node of the causal model.**

Weekly: **kill one big hypothesis** — [campaigns/README.md](../campaigns/README.md)

Metrics: [METRICS.md](../METRICS.md) — optimize **EIG** (uncertainty reduction), not fact count.

Exit: [EXIT-CRITERIA.md](../EXIT-CRITERIA.md)

---

## Promotion rule

Move fact → `invariants.yaml` when **≥10 runs** without value change (or research gate closed).

---

## Scripts

```bash
~/snd_repair/resolution/scripts/evidence/evidence-debt.sh
~/snd_repair/resolution/scripts/campaigns/campaign-status.sh
```
