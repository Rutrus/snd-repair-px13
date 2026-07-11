# Run p8-0010 — PCI INTx status at STAT1 events (Case B)

English (canonical). **2026-07-11** · boot after 0010 install · Phase **8.3**

Snapshots:

- `validation/.state/irq-pre-suspend-20260711T191155.txt`
- `validation/.state/irq-post-resume-20260711T191329.txt`

Suspend/resume: **2026-07-11 19:12:32** (tight cycle)

---

## PHASE10 witnesses

| When | resume | stat1 | intx_disable | intx_status | t_mgr_ms | handler |
|------|--------|-------|--------------|-------------|----------|---------|
| `irq_handler` (boot) | 0 | 0x4 | 0 | **1** | -1 | ✓ |
| `post_delay` (resume) | 1 | 0x4 | 0 | **0** | 51 | ✗ |

Additional resume witnesses:

- `handler_since_pm=0`
- `/proc/interrupts` IRQ 160: sum **62→62 delta=0**
- RT721: **-110** (+5272 ms)

---

## Classification: **Case B**

STAT1 latched (`0x4`) but **`PCI_STATUS.Interrupt Status=0`** on resume, while boot with same STAT1 shows **`intx_status=1`** and handler delivery.

**Inference:** ACP70 internal event is visible in MMIO but **does not propagate to PCI config interrupt status** after s2idle — points to **ACP interrupt bridge / firmware**, not Linux IRQ descriptor (E already falsified).

---

## Experimental phase

**Closed.** No further driver patches unless maintainer requests specific register/step.

Next: minimal upstream report with negative-proof table including 0010.

---

## Related

| Doc | Role |
|-----|------|
| [0010-pci-intx-observe.md](0010-pci-intx-observe.md) | Protocol |
| [0009-run-falsify-E-fail.md](0009-run-falsify-E-fail.md) | Prior falsification |
