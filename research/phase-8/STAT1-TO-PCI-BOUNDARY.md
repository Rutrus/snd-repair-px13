# STAT1 → PCI INTx boundary — register archaeology

English (canonical). Phase **8.3** — after falsification A/B/E closed the driver-side hypotheses.

**Project goal (updated):** deliver the **smallest possible proof** to maintainers of where propagation stops — not find a speculative fix.

---

## The active frontier

```text
ACP_EXTERNAL_INTR_STAT1 = 0x4     [observed @ ~51 ms post-D0 on resume]
        │
        │  <-- propagation stops here (inference + A/B/E falsification)
        │
IO-APIC GSI 13 / PCI INTx pin
        │
generic_handle_irq()
        │
acp63_irq_handler()               [never on resume — since_pm=0]
```

---

## Public register map (in-tree)

Source: `linux-source-7.0.0/include/sound/acp63_chip_offset_byte.h` + `sound/soc/amd/ps/`.

The **external interrupt block** exposed to the driver is exactly five MMIO registers:

| Offset | Symbol | Role |
|--------|--------|------|
| `0x1241A00` | `ACP_EXTERNAL_INTR_ENB` | Global enable |
| `0x1241A04` | `ACP_EXTERNAL_INTR_CNTL` | STAT0 unmask |
| `0x1241A08` | `ACP_EXTERNAL_INTR_CNTL1` | STAT1 unmask |
| `0x1241A0C` | `ACP_EXTERNAL_INTR_STAT` | STAT0 pending (W1C) |
| `0x1241A10` | `ACP_EXTERNAL_INTR_STAT1` | STAT1 pending (W1C) |

**Not found in public headers or driver:**

- `IRQ_ASSERT`, `IRQ_ROUTE`, `IRQ_PENDING`, `RAW_STATUS`, or any register between STAT and PCI legacy

Nearby ACP70-specific symbols that **are** in-tree but are **not** a STAT→PCI bridge readout:

| Offset | Symbol | Notes |
|--------|--------|-------|
| `0x1241400` | `ACP_PME_EN` | Written `1` on init/resume; PME enable, not INTx status |
| STAT1 bits 26–27 | `ACP70_SDW0/1_PME_STAT` | Wake/PME status bits; handler clears them; distinct from bit 2 (`ACP_SDW1_STAT`) |

**Conclusion:** There is **no documented MMIO “INT_ASSERT”** register in the open-source ACP70 driver tree. Answering “does the device assert PCI INTx?” cannot rely on an undocumented `readl()` without AMD docs or maintainer input.

---

## PCI config space probe (0010)

**No MMIO bridge register** in public ACP70 headers between STAT and PCI pin.

**Alternative:** read `PCI_STATUS` bit 3 (`PCI_STATUS_INTERRUPT`) + `PCI_COMMAND_INTX_DISABLE` at:

- `post_delay` when `STAT1=0x4` (resume)
- `irq_handler_enter` when `STAT1 & ACP_SDW1_STAT` (boot baseline)

**Spec basis:** PCI Local Bus Spec 3.0 — Interrupt Status reflects device interrupt state; with INTX_DISABLE clear, status=1 implies INTx# asserted. Kernel `pci_check_and_mask_intx()` uses the same bit for shared IRQ demux.

**Caveat:** rare non-compliant devices; log both command and status bits. ACP uses legacy INTx only (`msi=0`).

Experiment: [experiments/0010-pci-intx-observe.md](experiments/0010-pci-intx-observe.md).

---

## One remaining cheap experiment (observation only)

**Question:** When `STAT1=0x4` at `post_delay`, is the **PCI config INTx status bit** set?

**Method:** At the existing `post_delay` snapshot site (manager `intr_decode`), add **one** `pci_read_config_word(pci, PCI_STATUS)` and log bit 8 (`PCI_STATUS_INTERRUPT`, shown as `INTx+`/`INTx-` in `lspci`).

| Outcome | Meaning |
|---------|---------|
| `INTx+` at post_delay, handler=0 | Linux/delivery gap **after** PCI pin (IO-APIC, descriptor, masking) |
| `INTx-` at post_delay, STAT1=0x4 | Gap **inside ACP** or firmware — STAT latched but pin never asserted |
| Same on boot @ first SDW1 IRQ | Baseline for comparison |

Patch proposal: [proposed/0010-pci-intx-status-observe.patch](proposed/0010-pci-intx-status-observe.patch).

**Not planned after this:** further `ps-common.c` falsification patches; Patch D optional only.

---

## Falsification closed (software layers)

| Experiment | Layer | Result |
|------------|-------|--------|
| 0006a | Downstream SDW path | Manual worker **restores** enumeration |
| Patch A | STAT1 preclear before ENB | **FAIL** |
| Patch B | INTR block cold-reset | **FAIL** |
| Patch E | Linux `enable_irq()` on resume | **FAIL** |
| 0008 / E descriptor capture | IRQ desc registered, `wakeup=disabled`, unchanged | No desc corruption observed |

---

## If 0010 is inconclusive or INTx-

Stop exploratory patches. Prepare **minimal upstream report** (negative proof table + single maintainer question on ACP70 INTx re-arm after s2idle).

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0009-run-falsify-E-fail.md](experiments/0009-run-falsify-E-fail.md) | Last falsification |
| [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md) | MMIO matrix |
| [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) | Update **after** 0010 (or if skipped) |
