# Campaigns — weekly hypothesis kills

English (canonical). **Max 2 active+converging** campaigns in flight.

> Each week: **kill one big hypothesis**, not produce ten small facts.

Phase shift: **exploratory → confirmatory** (C02 converging = validating conclusion).

---

## Lifecycle

```text
ACTIVE       exploring — multiple outcomes still plausible
    ↓
CONVERGING   confirmatory — one verification run before archive
    ↓
KILLED | SUCCEEDED
```

| Status | Meaning |
|--------|---------|
| **active** | Still exploring |
| **converging** | Conclusion almost set — strict closure gates remain |
| **killed** | Hypothesis/path ruled out with documented gates |
| **succeeded** | Success condition met |
| **parked** | Deferred |

---

## Current (2026-07-12)

| ID | Status | Phase |
|----|--------|-------|
| [C01-intx-bridge](C01-intx-bridge/campaign.yaml) | **active** | confirmatory_cause |
| [C02-pci-reprobe](C02-pci-reprobe/campaign.yaml) | **killed** | RUN-09 — L4 closed |
| C03-firmware | parked | — |
| C04-runtime-pm | parked | — |

---

## C02 strict closure (not Edge FAIL alone)

| Gate | Requirement |
|------|-------------|
| **G1** | S2 certified W2+ |
| **G2** | R07 pci_reset OK |
| **G3** | BEFORE/AFTER snapshot valid |
| **G4** | Relevant diff unchanged (runtime_pm, pci_dstate, pci_status **word**) |

All four + ALSA fail → **C02 KILLED** with `kill_statement` in campaign.yaml.

If `pci_status` word changes (e.g. `0x0006` → `0x000e`): **do not kill** — record F014+ first.

```bash
~/snd_repair/resolution/scripts/campaigns/assess-c02-closure.sh
```

---

## Schema

```yaml
status: active|converging|parked|killed|succeeded
phase: exploratory|confirmatory|confirmatory_cause
kill_closure:  # optional — strict gates
```

---

## Rules

1. ≤2 **active+converging** combined.
2. Converging = one confirmatory run, not open exploration.
3. Accepted models → [evidence/accepted_models.yaml](../evidence/accepted_models.yaml)

---

## Related

- [METRICS.md](../METRICS.md) · [EXIT-CRITERIA.md](../EXIT-CRITERIA.md)
- [evidence/accepted_models.yaml](../evidence/accepted_models.yaml)
