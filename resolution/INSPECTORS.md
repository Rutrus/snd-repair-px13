# Inspectors — read-only probes (no recovery, no state change)

English (canonical). Two families: [observability/README.md](observability/README.md)

| Family | Question | Examples |
|--------|----------|----------|
| **Snapshot** | How is the system? | I01, I03, `_evidence-snapshot.sh` |
| **Timeline** | What happened? | I02, PHASE10, RT721 journal |

Graph: [evidence/graph.md](evidence/graph.md) · Facts: [evidence/facts.yaml](evidence/facts.yaml)

---

## I01 — Snapshot — **CLOSED**

**Facts:** F004 `runtime_usage=0`, F005 `runtime_status=active`

```bash
sudo ~/snd_repair/resolution/scripts/inspectors/I01-runtime-pm-blockers.sh
```

**Graph:** H_REFCNT falsified in [hypotheses.yaml](evidence/hypotheses.yaml)

---

## I02 — Timeline — **OPEN**

**Observation:** O_IOMMU — Type A/B/C vs PHASE10

```bash
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh since-last-resume
```

**Debt:** H_DMA high — see `scripts/evidence/evidence-debt.sh`

---

## Planned

| ID | Family | Topic |
|----|--------|-------|
| I03 | Snapshot | PCI PM / `runtime_idle` |
| I04 | Timeline | ACPI power resources |

---

## Edge execution states

| Execution | Meaning |
|-----------|---------|
| **PASS** | Transition ran → ALSA OK |
| **FAIL** | Transition ran → ALSA still broken |
| **BLOCKED** | Transition never executed |

---

## Priority

1. I02 Timeline → pay down H_DMA debt
2. E07 Reprobe → O_E07_DIFF + I02 again
3. Update **one** fact or hypothesis per run
