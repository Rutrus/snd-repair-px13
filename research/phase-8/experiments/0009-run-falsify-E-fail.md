# Run p8-falsify-E-fail — Patch E falsified (enable_irq on system resume)

English (canonical). **2026-07-11** · Phase **8.2**

Snapshots:

- pre: **not captured** for this cycle (compare script paired stale `irq-pre-suspend-20260711T181734.txt`)
- post: `validation/.state/irq-post-resume-20260711T183302.txt`

Patch: [../proposed/0009e-enable-irq-resume.patch](../proposed/0009e-enable-irq-resume.patch)

Suspend/resume: **2026-07-11 18:32:14** (tight cycle — same second in journal)

---

## Binary question

Does explicit `enable_irq(pci->irq)` at the start of `snd_acp_resume()` restore Linux IRQ delivery after s2idle?

**Answer: NO.**

---

## Witnesses (resume=1)

| Witness | Result |
|---------|--------|
| `PHASE9 falsify patch=E irq=160` | `enable_irq()` ran |
| `pm_resume_done stat1=0x0` | ✓ |
| `post_delay STAT1=0x4 STAT&mask=0x4` | ✓ @ ~51 ms |
| `irq_handler_enter resume≥1` | **0** |
| `handler_since_pm` | **0** |
| `handler_total` at irq_stats | **306** (unchanged in post snapshot) |
| RT721 | **-110** @ +5209 ms |
| Descriptor post-resume | `actions=ACP_PCI_IRQ`, `chip=IR-IO-APIC hwirq=13`, `wakeup=disabled`, `spurious count=0` |

---

## Closed hypothesis

**“Linux IRQ descriptor remained disabled/masked after s2idle; driver must call `enable_irq()` on resume.”**

Explicit re-enable before `acp_hw_resume()` does not change behaviour. Descriptor remains registered; handler still never enters during the s2idle window.

---

## Falsification phase complete

| Patch | Layer | Result |
|-------|-------|--------|
| A | STAT1 preclear before ENB | ❌ FAIL |
| B | INTR block cold-reset | ❌ FAIL |
| E | Linux `enable_irq()` on resume | ❌ FAIL |

**Stop exploratory patches.** Next: negative-proof upstream report + maintainer question on ACP70 INTx delivery after s2idle.

Patch D (`pci_set_master`) optional for completeness only — low prior after E.

---

## Related

| Doc | Role |
|-----|------|
| [0009-run-falsify-B-fail.md](0009-run-falsify-B-fail.md) | Prior falsification |
| [LINUX-IRQ-DESCRIPTOR-AUDIT.md](../LINUX-IRQ-DESCRIPTOR-AUDIT.md) | Static IRQ audit |
| [../../phase-6/UPSTREAM-REPORT-DRAFT.md](../../phase-6/UPSTREAM-REPORT-DRAFT.md) | Update after E |
