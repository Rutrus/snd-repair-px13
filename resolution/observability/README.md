# Observability — read-only inspectors

English (canonical). Two families — different questions:

| Family | Question | Updates |
|--------|----------|---------|
| **Snapshot** | How is the system *now*? | `facts.yaml` instantaneous fields |
| **Timeline** | What *happened*? | `facts.yaml` events + `O_*` observations |

Graph: [evidence/graph.md](../evidence/graph.md) · Facts: [evidence/facts.yaml](../evidence/facts.yaml)

---

## Snapshot inspectors

Instantaneous state — no journal ordering.

| ID | Script | Facts |
|----|--------|-------|
| **I01** | `I01-runtime-pm-blockers.sh` | F004, F005 |
| I03 | (planned) PCI PM callbacks | H_INTERNAL_PM |
| lib | `_evidence-snapshot.sh` | used by R07 Reprobe differential |

```bash
sudo ~/snd_repair/resolution/scripts/inspectors/I01-runtime-pm-blockers.sh
```

---

## Timeline inspectors

Event ordering — journal, PHASE10, IOMMU, RT721.

| ID | Script | Facts / observations |
|----|--------|----------------------|
| **I02** | `I02-iommu-faults.sh` | F012, O_IOMMU (Type A/B/C) |
| I04 | (planned) ACPI PM timeline | — |

```bash
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh since-last-resume
```

**I02 fields:** Domain · Device · PASID · Address · Flags · perm hint · timing class

**Discipline:** Timeline observability ≠ primary hypothesis until stable across runs.

---

## Status

| ID | Family | Status | Graph |
|----|--------|--------|-------|
| I01 | Snapshot | **CLOSED** | F004, F005 → H_REFCNT falsified |
| I02 | Timeline | **OPEN** | O_IOMMU → H_DMA debt |
| I03 | Snapshot | planned | H_INTERNAL_PM |
| I04 | Timeline | planned | — |

---

## Reprobe differential (E07 / R07)

Edge type **Reprobe** — snapshot before/after PCI destroy+recreate. See [EDGE-TYPES.md](../EDGE-TYPES.md).

---

## Related

- [INSPECTORS.md](../INSPECTORS.md)
- [evidence/README.md](../evidence/README.md)
- [evidence/hypotheses.yaml](../evidence/hypotheses.yaml) — evidence_debt
