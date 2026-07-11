# Phase 8 — ACP platform IRQ path (ACP70)

English (canonical). **Phase 7 is frozen** — no SoundWire manager experiments (delays, manual schedule, STAT decode sweeps).

**Upstream context:** [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md)

---

## Gap status after 8.1

```text
resume → manager_reset → bring-up OK
   │
   ▼
STAT1 & mask = 0x4 (~50 ms)          [Fact]
   │
   ▼
Linux /proc/interrupts               [Fact: delta=0 — 8.1]
   │
   ▼
acp63_irq_handler()                  [Fact: since_pm=0 — 8.1]
   │
   ▼
schedule_work → …                    [Fact: OK if forced — 0006a]
   │
   ▼
RT721 attach                         boot ✓ / resume ✗
```

**8.1 closed:** Not handler-ignore — **no Linux IRQ / no handler invocation** while STAT pending.

**Phase 8 is now implementation investigation:** find which **ACP resume code path** should raise legacy IRQ and does not.

---

## Out of scope

- Phase 7 delays, timers, manual `schedule_work`, STAT decode sweeps
- Further SoundWire instrumentation (saturated after 8.1)
- RT721 / TAS2783 unless ACP path diff requires it

---

## Mini-objectives

### 8.1 — Locate the exact boundary ✅ CLOSED

**Milestone run:** [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md)

Three witnesses: STAT pending + `handler_since_pm=0` + `/proc/interrupts` delta=0.

---

### 8.2 — Last write before STAT (code audit, ACP only)

**Question:** What is the last `writel()` to ACP interrupt registers before `STAT1=0x4` — and how does that differ from boot?

**Method:** Register ownership table + resume call map — **no new printk experiments**, no delay sweeps.

**Deliverable:** [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md)

**Boot vs resume:** Not a wide diff table — only fields that affect **legacy IRQ delivery** (`ENB`, `CNTL*`, `request_irq` lifetime, `sdw_en_stat` fast path).

---

### 8.3 — IRQ flow diagram

Merged into [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) (top-down path + boot/resume checklist).

---

## Parallel track — upstream outreach

Ask maintainers:

> ACP70 shows pending `ACP_EXTERNAL_INTR_STAT1` after s2idle resume, but legacy `ACP_PCI_IRQ` does not increment and `acp63_irq_handler` is never entered; cold boot with the same STAT bit works. Is a missing step in `snd_acp70_resume` / `acp70_enable_interrupts` familiar?

Attach: [0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) + [UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md).

---

## Roadmap

| Step | Action |
|------|--------|
| 1 | Phase 7 frozen ✅ |
| 2 | Upstream draft polished ✅ |
| 3 | **8.1** closed ✅ [0008-run-boundary-c1](experiments/0008-run-boundary-c1.md) |
| 4 | **8.2** code audit → [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) |
| 5 | Candidate patch **or** upstream with bounded question |
| 6 | Optional: 2–3 more `/proc/interrupts` cycles (same boot) for citation only |

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) | **8.1 milestone** |
| [experiments/0008-irq-boundary-trace.md](experiments/0008-irq-boundary-trace.md) | 0008 patch protocol |
| [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) | 8.2 + 8.3 register map |
| [../phase-7/INDEX.md](../phase-7/INDEX.md) | Frozen Phase 7 |
