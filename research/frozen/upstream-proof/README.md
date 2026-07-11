# Frozen — upstream proof (research complete)

English (canonical). **No new Phase 9.** Local investigation stops here unless an upstream maintainer requests a specific register or step.

---

## What this freeze means

Research answered:

> **Where does the system stop working?**

Answer (demonstrated):

```text
ACP manager STAT1 pending @ ~50 ms after resume
        ↓
Legacy INTx not delivered to acp63_irq_handler()
        ↓
Downstream SoundWire path is OK if amd_sdw_irq_thread runs (0006a)
```

Further observation-only instrumentation has **marginal value**. Engineering work moves to [`../../../resolution/`](../../../resolution/). Research re-opens **only** on **Stable Edge** (5/5) — [../../../resolution/EDGE-FRAMEWORK.md](../../../resolution/EDGE-FRAMEWORK.md).

---

## Canonical deliverables (do not rewrite)

| Doc | Role |
|-----|------|
| [../../phase-8/UPSTREAM-REPORT.md](../../phase-8/UPSTREAM-REPORT.md) | **Submittable** short report |
| [../../phase-6/UPSTREAM-REPORT-DRAFT.md](../../phase-6/UPSTREAM-REPORT-DRAFT.md) | Long-form evidence |
| [../../phase-8/UPSTREAM-EMAIL-DRAFT.txt](../../phase-8/UPSTREAM-EMAIL-DRAFT.txt) | Mail template |
| [../../phase-8/experiments/0008-run-boundary-c1.md](../../phase-8/experiments/0008-run-boundary-c1.md) | 8.1 milestone |
| [../../phase-8/experiments/0010-run-pci-intx-observe.md](../../phase-8/experiments/0010-run-pci-intx-observe.md) | PCI INTx observation |
| [../../phase-6/KNOWN-FACTS.md](../../phase-6/KNOWN-FACTS.md) | Demonstrated vs not |

---

## Phase status at freeze

| Phase | Status |
|-------|--------|
| Phase 6 | Observation complete |
| Phase 7 | Frozen — delivery boundary closed |
| Phase 8 | Frozen — IRQ path delimited; falsification A **FAIL**; B/E/D optional for maintainer only |

Index: [../../phase-8/INDEX.md](../../phase-8/INDEX.md)

---

## If upstream responds

- Re-open **research** only for the specific sequence they name.
- Do **not** mix maintainer-requested traces into `resolution/` workarounds without labeling.

---

## If the goal is “laptop works tomorrow”

→ [`../../../resolution/README.md`](../../../resolution/README.md)
