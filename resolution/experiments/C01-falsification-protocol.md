# C01 — Falsification-only experiments (no exploratory patches)

English (canonical). Goal: **falsify M_INTX_CORE** or find intermediate observation point — not new fixes.

---

## Priority order

| Rank | Experiment | EIG | Notes |
|------|------------|-----|-------|
| 1 | **ACP intermediate register** search | high | Before PCI polling |
| 2 | Maintainer Q1–Q6 | enormous | See C01-upstream-handoff.md |
| 3 | Boot vs resume MMIO diff (documented regs only) | medium | Read-only |
| — | PCI_STATUS poll 1ms only | **low** | Insufficient alone |

---

## Why not 1ms PCI polling first

If `intx_status` pulses ~50µs, 1ms sampling never sees it:

```text
IRQ bit:  ■■
poll:        ↑     ↑     ↑   (1ms)
```

**Conclusion:** polling-only experiment could falsely confirm "never asserted."

**Better:** locate ACP MMIO readout **upstream** of PCI_STATUS (maintainer map or public header archaeology). One stable register beats infinite PCI polls.

---

## Falsification targets (M_INTX_CORE)

| ID | If observed | Effect |
|----|-------------|--------|
| FALSIFY_1 | `intx_status=1` + handler=0 | Move gap past PCI config |
| FALSIFY_2 | `STAT1≠0x4` on FAIL | Break witness chain |
| FALSIFY_3 | Maintainer names different observation point | Revise model |

---

## Hypothesis competitors (cause — not core model)

| ID | Name | Priority |
|----|------|----------|
| H_CAUSE_CLK | Clock/power gated routing (Alt A) | **high** |
| H_CAUSE_FABRIC | Fabric registration lost (Alt D) | **high** |
| H_CAUSE_TRANSIENT | Transient bit cleared (Alt B) | **low** |

Do not invest weeks in reverse-engineering proprietary block if maintainer can answer Q1–Q4.

---

## Discipline

- No new Patch F/G without single falsification question
- No E08 unless new evidence reopens L4
- Update **one** node per run (fact, assumption, or hypothesis confidence)
