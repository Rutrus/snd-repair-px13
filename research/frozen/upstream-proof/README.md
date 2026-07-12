# Frozen — upstream proof (Phase 6–8)

English (canonical). **Frozen** as of 2026-07-12. **No new Phase 9 observation-only traces.**

**Unified model:** [../UNIFIED-CAUSAL-MODEL.md](../UNIFIED-CAUSAL-MODEL.md) — this freeze covers **IRQ delivery boundary evidence** (remote cause **candidate**). It does **not** prove that lost IRQ causes PCM2 `hw_params` `-EINVAL`.

**Active local work:** [../track-PCM-smartamp-hwparams.md](../track-PCM-smartamp-hwparams.md) (Q1: rejecting callback).

---

## What this freeze demonstrated

> **Where does the ACP70 resume IRQ path diverge from boot in FAIL runs?**

Answer (**facts** — cite in upstream mail):

```text
ACP manager STAT1 pending @ ~50 ms after resume
        ↓
Legacy INTx not delivered to acp63_irq_handler()
        (/proc/interrupts delta = 0; handler_since_pm = 0)
        ↓
Downstream SoundWire path is OK if amd_sdw_irq_thread runs (0006a)
```

---

## What this freeze did **not** demonstrate

| Claim | Status |
|-------|--------|
| Lost IRQ **causes** PCM2 `-EINVAL` | **Not demonstrated** — coherent model only |
| Fixing IRQ alone restores speakers | **Not demonstrated** |
| `tas_sdw_hw_params` is the rejecting function | **Open** — Track PCM2 Q1 |

Keep Phase 6–8 reports and Track PCM2 trace **separate** in maintainer communication until Q1 closes.

---

## Canonical deliverables (do not rewrite)

| Doc | Role |
|-----|------|
| [../phase-8/UPSTREAM-REPORT.md](../phase-8/UPSTREAM-REPORT.md) | Short IRQ-boundary report |
| [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) | Long-form evidence |
| [../phase-8/UPSTREAM-EMAIL-DRAFT.txt](../phase-8/UPSTREAM-EMAIL-DRAFT.txt) | Mail template |
| [../phase-8/experiments/0008-run-boundary-c1.md](../phase-8/experiments/0008-run-boundary-c1.md) | 8.1 milestone |
| [../phase-6/KNOWN-FACTS.md](../phase-6/KNOWN-FACTS.md) | Demonstrated vs not |

---

## Phase status at freeze

| Phase | Status |
|-------|--------|
| Phase 6 | Observation complete |
| Phase 7 | Frozen — delivery boundary closed |
| Phase 8 | Frozen — falsification A FAIL; B/E/D maintainer-only |

---

## If upstream responds

Re-open **research** only for the specific sequence they name. Label any maintainer-requested trace separately from Track PCM2 / resolution work.

---

## If the goal is “laptop works tomorrow”

→ Track PCM2 Q1 first · [../../resolution/README.md](../../resolution/README.md) (recovery lines paused)
