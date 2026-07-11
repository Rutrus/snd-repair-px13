# Phase 8 — ACP platform IRQ path (ACP70)

English (canonical). **Phase 7 is frozen** — no SoundWire manager experiments (delays, manual schedule, STAT decode sweeps).

**Upstream context:** [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md)

**Strategy (post–8.3):** Experimental reduction **complete** (0010 Case B). **Upstream report:** [UPSTREAM-REPORT.md](UPSTREAM-REPORT.md).

**Local investigation frozen** — see [../frozen/upstream-proof/README.md](../frozen/upstream-proof/README.md). Engineering: [../../resolution/README.md](../../resolution/README.md).

**Upstream send:** [UPSTREAM-EMAIL-DRAFT.txt](UPSTREAM-EMAIL-DRAFT.txt) · [UPSTREAM-SEND-CHECKLIST.md](UPSTREAM-SEND-CHECKLIST.md) · report [UPSTREAM-REPORT.md](UPSTREAM-REPORT.md)

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

**Phase 8 is now code archaeology:** find which **register sequence or hardware bridge** should deliver legacy IRQ after s2idle and does not.

---

## Out of scope

- Phase 7 delays, timers, manual `schedule_work`, STAT decode sweeps
- Further SoundWire / manager / RT721 instrumentation (**saturated** after 8.1)
- New experiments unless a **concrete asymmetry** appears in the register matrix

---

## Mini-objectives

### 8.1 — Locate the exact boundary ✅ CLOSED

**Milestone run:** [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md)

Three witnesses: STAT pending + `handler_since_pm=0` + `/proc/interrupts` delta=0.

---

### 8.2 — Hypothesis falsification (patches A–D) — **frozen** (A FAIL; B/E/D maintainer-only)

**No new instrumentation.** One patch per reboot. Protocol: [experiments/0009-falsification-matrix.md](experiments/0009-falsification-matrix.md)

| Patch | Status / next |
|-------|----------------|
| **A** | ❌ FAIL — [0009-run-falsify-A-fail](experiments/0009-run-falsify-A-fail.md) |
| **B** | **Next** — cold-reset INTR in `acp70_enable_interrupts()` |
| **E** | `enable_irq()` — Linux descriptor rearm |
| **D** | `pci_set_master` — last cheap PCI test |

Cross-version PM: [ACP-CROSS-VERSION-PM.md](ACP-CROSS-VERSION-PM.md)

**Rama B:** [UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) — hold until falsification complete.

---

### 8.3 — IRQ flow diagram

Merged into [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) (top-down path + boot/resume checklist).

---

## Parallel track — upstream outreach

Ask maintainers (concrete):

> During system resume on ACP70 we consistently observe `ACP_EXTERNAL_INTR_STAT1 = ACP_SDW1_STAT` about 50 ms after manager reset, but the shared legacy interrupt never reaches `acp63_irq_handler()` and `/proc/interrupts` does not increment. On cold boot the same status bit immediately results in IRQ delivery. Is there any ACP70-specific interrupt re-arm, bridge, or platform sequence outside `acp70_enable_interrupts()` required after s2idle resume?

Attach: [0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) + [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md) + [UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md).

---

## Roadmap

| Step | Action |
|------|--------|
| 1 | Phase 7 frozen ✅ |
| 2 | Upstream draft polished ✅ |
| 3 | **8.1** closed ✅ [0008-run-boundary-c1](experiments/0008-run-boundary-c1.md) |
| 4 | Call matrix + STAT1 ack audit → [ACP-BOOT-VS-RESUME-CALLS.md](ACP-BOOT-VS-RESUME-CALLS.md) ✅ |
| 5 | Register matrix → [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md) ✅ |
| 6 | Upstream git → [UPSTREAM-GIT-ACP70-PM.md](UPSTREAM-GIT-ACP70-PM.md) ✅ |
| 7 | Code archaeology docs ✅ |
| 8 | **8.2 falsify A→D** → [0009-falsification-matrix](experiments/0009-falsification-matrix.md) |
| 9 | Upstream mail or fix patch (Rama B) |

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) | **8.1 milestone** |
| [experiments/0008-irq-boundary-trace.md](experiments/0008-irq-boundary-trace.md) | 0008 patch protocol |
| [experiments/0009-run-falsify-A-fail.md](experiments/0009-run-falsify-A-fail.md) | Patch A **FAIL** |
| [ACP-CROSS-VERSION-PM.md](ACP-CROSS-VERSION-PM.md) | ACP5x/6x/63/70 disable/enable compare |
| [ACP-IRQ-REGISTER-OWNERSHIP.md](ACP-IRQ-REGISTER-OWNERSHIP.md) | Register writers, facts vs open |
| [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) | Call map + last-write timeline |
| [UPSTREAM-GIT-ACP70-PM.md](UPSTREAM-GIT-ACP70-PM.md) | Upstream commit archaeology |
| [../phase-7/INDEX.md](../phase-7/INDEX.md) | Frozen Phase 7 |
