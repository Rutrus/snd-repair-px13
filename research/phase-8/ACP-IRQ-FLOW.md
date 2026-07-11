# ACP70 IRQ flow — working diagram (Phase 8.3)

English (canonical). **Draft placeholder** — fill from code read of `sound/soc/amd/ps/`.

Status: **not started**. Do not treat as fact until each step is cited to source lines.

---

## Target diagram

```text
ACP_EXTERNAL_INTR_STAT0/1  (hardware pending bits)
        │
        ▼
ACP interrupt controller
  (CNTL / ENB / mask — ps-common.c, amd_manager external regs)
        │
        ▼
Platform line → IO-APIC GSI 13 → Linux IRQ N  (ACP_PCI_IRQ, legacy)
        │
        ▼
acp63_irq_handler()                    pci-ps.c
        │
        ├── sdw0_irq branch
        └── sdw1_irq branch            (STAT1 bit → ack)
        │
        ▼
schedule_work(amd_sdw_irq_thread)      soundwire-amd (if SDW path)
        │
        ▼
amd_sdw_irq_thread → enumeration
```

---

## Boot vs resume checklist (8.2)

| Step | Boot observed | Resume observed | Source function |
|------|---------------|-----------------|-----------------|
| PCI probe / `request_irq` | | | |
| `acp_hw_resume` | | | |
| `acp70_enable_interrupts` | | | |
| host-wake CNTL1 | | | |
| Handler runs on STAT1=0x4 | Yes (0007) | No (0007 correlate) | |

---

## Notes

Add line references and register names as you read the tree. Link findings back to [INDEX.md](INDEX.md).
