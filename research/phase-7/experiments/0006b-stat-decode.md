# Experiment 0006b — INTR_STAT / INTR_CNTL decode (observation)

English (canonical). **Observation only** — no `schedule_work`, no ping forcing. Answers: **what is `STAT=0x4`**, and does **`INTR_CNTL=0x400004`** match the enabled manager mask?

Can ship as **extra probes only** — **separate commit** from 0006a (observation vs intervention; bisect-friendly).

---

## Why this exists

0005/d50 avoided a false conclusion: `0x4` is **not** `ACP_SDW0_STAT` (`0x200000`).

| Observation (d50) | Implication |
|-------------------|-------------|
| `intr_stat_post_delay = 0x4` | Bit **2** set on `ACP_EXTERNAL_INTR_STAT(instance)` |
| `intr_cntl_post_enable = 0x400004` | CNTL has **BIT(2) and BIT(22)** — not the same as `AMD_SDW0_EXT_INTR_MASK` alone (`0x200000` = BIT 21) |
| No `irq_handler_enter` | `pci-ps.c` SDW0 path checks **BIT(21)** on `ACP_EXTERNAL_INTR_STAT`, not BIT(2) on that register |

Before any manual IRQ bypass, decode **which register** and **which named bits** are active.

---

## Reads (one snapshot post-delay or post-D0)

For **both** manager instances `i ∈ {0,1}` (even if PX13 only uses instance 0):

```text
CNTL(i)  = readl(acp_mmio + ACP_EXTERNAL_INTR_CNTL(i))
STAT(i)  = readl(acp_mmio + ACP_EXTERNAL_INTR_STAT(i))
```

Global (pci-ps view):

```text
STAT_g  = readl(acp63_base + ACP_EXTERNAL_INTR_STAT)    # 0x1A0C
STAT1_g = readl(acp63_base + ACP_EXTERNAL_INTR_STAT1)  # 0x1A10
```

Confirm: `STAT(0)` should equal `STAT_g`; `STAT(1)` should equal `STAT1_g`.

---

## Decode table (print in dmesg)

Use known symbols from `acp63.h` / `amd_manager.h` / `pci-ps.c`:

### `ACP_EXTERNAL_INTR_STAT` (0x1A0C) — global / instance 0

| Bit mask | Symbol | pci-ps handler |
|----------|--------|----------------|
| `0x200000` | `ACP_SDW0_STAT` | Yes → `schedule_work(irq_thread)` |
| `0x20000000` | `ACP_ERROR_IRQ` | Yes → clear + error path |
| `0x10000` | `BIT(PDM_DMA_STAT)` (PDM) | Yes |
| `0x1F800000` | `ACP70_SDW_DMA_IRQ_MASK` region | DMA thread |
| `0x4` | *(no SDW0 symbol)* | **Not handled** for SDW on this register |

### `ACP_EXTERNAL_INTR_STAT1` (0x1A10) — instance 1 / global STAT1

| Bit mask | Symbol | pci-ps handler |
|----------|--------|----------------|
| `0x4` | `ACP_SDW1_STAT` | Yes → `schedule_work(irq_thread)` |
| `0x0C000000` | HOST_WAKE (bits 24–25) | wake path |
| `0x18000000` | PME (bits 26–27) | wake path |
| `0x1F8` | SDW1 DMA (STAT1) | DMA thread |

### Manager enable masks (`amd_enable_sdw_interrupts`)

| instance | `AMD_SDW*_EXT_INTR_MASK` | Expected CNTL bit |
|----------|--------------------------|-------------------|
| 0 | `0x200000` | BIT 21 |
| 1 | `4` | BIT 2 on `CNTL(1)` |

**Check:** does `CNTL(instance)` contain the expected mask bit? Why does d50 show `0x400004` on instance 0?

### Open question (document before upstream)

d50 logged `INTR_CNTL(0) = 0x400004` while `AMD_SDW0_EXT_INTR_MASK = 0x200000`:

```text
0x400004 = BIT(22) | BIT(2)
0x200000 = BIT(21)   ← manager_mask for instance 0
0x200000 = ACP_SDW0_STAT (handler test in pci-ps.c)
```

0006b must answer:

> **Who programs `INTR_CNTL` with `0x400004`, and why is the handler’s expected bit (BIT 21) not the one that appears enabled / pending?**

Trace in tree:

- `amd_enable_sdw_interrupts()` → `amd_updatel(..., ACP_EXTERNAL_INTR_CNTL(instance), manager_mask, manager_mask)`
- `acp70_enable_interrupts()` → `writel(ACP_ERROR_IRQ, ACP_EXTERNAL_INTR_CNTL)` (global base — same offset as `CNTL(0)`?)

If decode shows BIT(22) is another SDW-related enable, document the symbol. If CNTL and mask disagree on every FAIL, that is upstream-grade evidence without claiming a bug yet.

---

## Log format (single line per instance)

```text
PHASE7 ctx=amd fn=intr_decode link=%d resume=%d instance=%u
  cntl=0x%x stat=0x%x manager_mask=0x%x stat_and_mask=0x%x
  stat_bits: sdw0_stat=%u sdw1_on_stat0=%u error=%u pdm=%u
  cntl_bits: sdw0_mask=%u bit2=%u bit22=%u
```

Keep hex + named flags — not hex alone.

---

## Binary questions

1. **Register aliasing:** Is `STAT(0)` identical to `STAT_g` and `STAT(1)` to `STAT1_g` on FAIL?
2. **Instance mapping:** For `link_id=1`, what is `amd_manager->instance`?
3. **Mask consistency:** Is `CNTL(instance)` programmed with `manager_mask` or something else (e.g. `0x400004`)?
4. **Delayed bit identity:** Is delayed `0x4` on `STAT(0)` or only on `STAT(1)`?

---

## Outcomes → next step

| Result | Next |
|--------|------|
| `0x4` only on `STAT(0)`, never `stat & 0x200000` | 0006a likely negative; investigate CNTL programming / bit 22 |
| `0x4` on `STAT(1)` with `instance=0` | Possible instance/register mismatch in probes vs handler |
| `stat & manager_mask` set on FAIL | Proceed 0006a manual `schedule_work` |
| PASS run shows different decode | Golden diff for upstream |

---

## Run protocol

No separate sweep. Add decode probes to 0006a build or run once on:

- FAIL-1 with `delay_ms=50` (existing d50 conditions)
- Optional PASS capture if available
- Control `delay_ms=0`

No success/fail witness change — enriches interpretation of 0006a/0005.
