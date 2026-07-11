# ACP70 IRQ flow — register ownership and resume call map (Phase 8.2 + 8.3)

English (canonical). Code audit of `sound/soc/amd/ps/` for **where a legacy IRQ should be raised** after s2idle resume.

**Prerequisite facts:** [0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) — STAT pending, `handler_since_pm=0`, `/proc/interrupts` delta=0.

**8.2 question (narrow):** What is the **last `writel()` to ACP interrupt hardware** before `STAT1=0x4` appears ~51 ms after manager_reset — and does boot take a different path?

---

## Intended delivery path (top-down)

```text
SoundWire manager event
        │
        ▼
ACP_EXTERNAL_INTR_STAT1  bit pending (e.g. 0x4)
        │
        ▼
ACP interrupt controller
  ACP_EXTERNAL_INTR_ENB = 1
  ACP_EXTERNAL_INTR_CNTL* unmasked for that bit
        │
        ▼
Legacy PCI IRQ line (GSI 13, IO-APIC fasteoi)  →  Linux IRQ N
        │
        ▼
request_irq(..., acp63_irq_handler, ...)         pci-ps.c probe (once per boot)
        │
        ▼
acp63_irq_handler()
        │
        └── STAT1 & ACP_SDW1_STAT → writel ack → schedule_work(amd_sdw_irq_thread)
```

**8.1 fact:** Steps below `Linux IRQ N` do not run on resume=1 while STAT is pending.

---

## Register ownership (ACP IRQ-related)

Only writers in **`sound/soc/amd/ps/`** unless noted. `amd_manager` shares the same MMIO (`acp_mmio`) for `ACP_EXTERNAL_INTR_CNTL(ACP_SDW*)` — listed for **last-write timeline**, not for further SDW experiments.

| Register | Boot (`acp70_init`) | System resume | Primary writer(s) in tree |
|----------|---------------------|---------------|---------------------------|
| `ACP_EXTERNAL_INTR_ENB` | `writel(1, …)` | Full init: `1`; fast path: **no write** | `acp70_enable_interrupts()` · `acp70_disable_interrupts()` · `ps-common.c` |
| `ACP_EXTERNAL_INTR_CNTL` | `writel(ACP_ERROR_IRQ, …)` then cleared on deinit | Same on full init | `acp70_enable_interrupts()` / `acp70_disable_interrupts()` |
| `ACP_EXTERNAL_INTR_CNTL1` | See below | See below | `acp70_enable_sdw_host_wake_interrupts()` · `amd_enable_sdw_interrupts()` · `amd_sdw_host_wake_enable()` · `ps-sdw-dma.c` (DMA watermark bits) · handler ack paths |
| `ACP_EXTERNAL_INTR_STAT` | Cleared on deinit | Ack in handler only | `acp70_disable_interrupts()` · `acp63_irq_handler()` |
| `ACP_EXTERNAL_INTR_STAT1` | Cleared on deinit | Ack in handler / wake paths | `pci-ps.c` handler · `check_and_handle_acp70_sdw_wake_irq()` |
| `ACP_SW0/1_WAKE_EN` | Read-only in enable path | Suspend saves pad state | `acp70_enable_interrupts()` reads; wake handler writes `0` |
| `ACP_PME_EN` | `writel(1, …)` | Fast resume: `writel(1, …)` | `acp70_init()` · `snd_acp70_resume()` fast path |
| `ACP_SW_STATE_CHANGE_STATUS_MASK_*` | — | Manager bring-up | **`amd_manager.c`** (not ps/) |
| `ACP_ERROR_STATUS` | — | Cleared in error IRQ branch | `pci-ps.c` handler |

### `0xc00000` — exact source

```c
#define ACP70_SDW_HOST_WAKE_MASK  0x0C00000   /* acp63.h */

static void acp70_enable_sdw_host_wake_interrupts(void __iomem *acp_base)
{
    ext_intr_cntl1 = readl(ACP_EXTERNAL_INTR_CNTL1) | ACP70_SDW_HOST_WAKE_MASK;
    writel(ext_intr_cntl1, …);
}
```

Called from **`acp70_enable_interrupts()`** only when `ACP_SW0_WAKE_EN || ACP_SW1_WAKE_EN` is non-zero at init time.

**Not** from `check_and_handle_acp70_sdw_wake_irq()` (that path **acks** `STAT1` host-wake bits and clears `WAKE_EN`).

### `0x400004` — SDW1 manager mask (for timeline only)

`amd_enable_sdw_interrupts()` → `amd_updatel(acp_mmio, ACP_EXTERNAL_INTR_CNTL(ACP_SDW1), mask, mask)` with `AMD_SDW1_EXT_INTR_MASK = 4` → sets bit 2 in `CNTL1`.

Observed sequence on resume (p7-correlate-d50, p8-boundary-c1): **`0xc00000` (ps-common) → `0x400004` (amd_manager)** before STAT pending.

---

## System resume call map (ACP PCI driver)

```text
snd_acp_resume()                          pci-ps.c
    └── acp_hw_resume()
            └── snd_acp70_resume()        ps-common.c
                    │
                    ├── [fast] sdw_en_stat == true
                    │       writel(ZSC_DSP_CTRL, 0)
                    │       writel(PME_EN, 1)
                    │       return 0          ← NO acp70_enable_interrupts()
                    │
                    └── [full] sdw_en_stat == false
                            acp_hw_init() → acp70_init()
                                acp70_power_on / reset
                                acp70_enable_interrupts()
                                    ENB=1, CNTL0=ERROR
                                    optional acp70_enable_sdw_host_wake → CNTL1|=0xc00000
                                PME_EN=1
```

**Boot probe (once):**

```text
snd_acp63_probe()
    request_irq(pci->irq, acp63_irq_handler, …)   ← not repeated on system resume
```

**Critical fork:** `sdw_en_stat` is sampled at **suspend entry** from `ACP_SW0_EN | ACP_SW1_EN`. If SoundWire was enabled going into s2idle, resume may **skip** full `acp70_init()` and therefore **skip** `acp70_enable_interrupts()`.

p8-boundary-c1 logged `acp70_host_wake` → **full init path** on that cycle. Still no IRQ delivery — so the gap is not *only* the fast path, but the fast path remains a **boot vs resume asymmetry** to verify on the next code pass.

---

## Last writes before `STAT1=0x4` (resume=1, p8-boundary-c1)

Chronological, **ACP/platform only** up to manager `amd_enable_sdw_interrupts`:

| Order | When | Function | Register | Value |
|-------|------|----------|----------|-------|
| 1 | `pm_resume` | `acp70_enable_interrupts` | `INTR_ENB` | `1` |
| 2 | same | `acp70_enable_interrupts` | `INTR_CNTL0` | `ACP_ERROR_IRQ` |
| 3 | same | `acp70_enable_sdw_host_wake_interrupts` | `INTR_CNTL1` | **`0xc00000`** |
| 4 | same | `acp70_init` | `PME_EN` | `1` |
| 5 | manager bring-up | `amd_enable_sdw_interrupts` | `INTR_CNTL1` | **`0x400004`** (via `amd_updatel`, mask `0x4`) |
| 6 | same | `amd_enable_sdw_interrupts` | `SW_STATE_CHANGE_STATUS_MASK_*` | manager masks |
| … | +51 ms | *(hardware)* | `INTR_STAT1` read | **`0x4`** |
| — | +51 ms…+5 s | — | `/proc/interrupts` | **no increment** |
| — | same window | — | `acp63_irq_handler` | **not entered** |

**8.2 working hypothesis:** After row 5, something required to **pulse or unmask the legacy IRQ line** is still missing compared to boot — not “read STAT again later”.

Candidate areas (code read, not new experiments):

1. **`sdw_en_stat` fast path** — resume without `acp70_enable_interrupts()` when SW links stayed enabled.
2. **`request_irq` not re-run** — boot vs resume IRQ descriptor state (same IRQ# but enable/mask/affinity?).
3. **CNTL1 composition** — host-wake bits (`0xc00000`) vs manager SDW bit (`0x4`); boot `CNTL1=0x1e4` at handler entry vs resume `0x400004`.
4. **`ACP_EXTERNAL_INTR_ENB`** — still `1` at `pm_resume_done` on p8 run; verify unchanged at post_delay instant (read-only in existing logs).

---

## Boot reference (same machine, resume=0)

From p8-boundary-c1 boot section @ 17:17:08:

```text
irq_handler_enter irq=160 stat1=0x4 cntl1=0x1e4 enb=0x1
sdw1_irq → HANDLED → RT721 ATTACHED
```

| Field | Boot @ handler | Resume @ pm_resume_done | Resume @ post_delay (manager read) |
|-------|----------------|-------------------------|----------------------------------|
| `STAT1` | `0x4` | `0x0` | `0x4` |
| `CNTL1` | `0x1e4` | `0xc00000` | `0x400004` |
| Handler | entered | not entered | not entered |
| `/proc/interrupts` | increments | — | delta=0 |

**Action for implementation phase:** Diff **what boot `acp70_init` + probe + first manager enable** leaves in `CNTL1/ENB/IRQ core` vs **what resume leaves** after rows 1–5 above — without adding delay experiments.

---

## Files to read (priority)

```text
sound/soc/amd/ps/ps-common.c   acp70_init / enable / disable / snd_acp70_{suspend,resume}
sound/soc/amd/ps/pci-ps.c      request_irq, acp63_irq_handler, snd_acp_{suspend,resume}
sound/soc/amd/ps/acp63.h       ACP70_SDW_HOST_WAKE_MASK, STAT bit defs
sound/soc/amd/ps/ps-sdw-dma.c  CNTL* for DMA watermark (parallel IRQ source)
```

**Out of scope for next patch:** `amd_manager.c` behaviour changes until ACP resume path diff is understood.

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) | 8.1 milestone |
| [INDEX.md](INDEX.md) | Phase 8 roadmap |
| [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) | Upstream narrative |
