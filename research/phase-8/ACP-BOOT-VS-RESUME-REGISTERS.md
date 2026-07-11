# ACP70 boot vs resume — register write matrix (code archaeology)

English (canonical). Phase **8.2+** deliverable. **No new printk experiments** — static code read + logged values from frozen runs only.

**Prerequisite facts:** [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) (8.1 closed).

**Related:** [ACP-IRQ-REGISTER-OWNERSHIP.md](ACP-IRQ-REGISTER-OWNERSHIP.md) · [UPSTREAM-GIT-ACP70-PM.md](UPSTREAM-GIT-ACP70-PM.md) · [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md)

---

## Strategy (post–8.1)

Empirical SoundWire/manager instrumentation is **saturated**. Further experiments add little unless a **concrete software asymmetry** appears in this matrix.

Compare **registers and write order**, not function names:

| Type | Meaning |
|------|---------|
| **A** | Boot writes / does something resume never does |
| **B** | Resume writes / does something boot never does |
| **C** | Same register, different value at comparable milestone |
| **D** | Same register, same value, **different order** relative to IRQ arm |

---

## Closed chain (high confidence)

```text
resume
   ↓
ACP70 init OK
   ↓
amd_sdw_manager init OK
   ↓
STAT1 = 0x4 (~51 ms)
   ↓
❌ no Linux IRQ / no acp63_irq_handler()
   ↓
irq thread never runs
   ↓
RT721 timeout (-110)

schedule_work() manual  →  full downstream OK (0006a)
```

SoundWire manager, RT721, and DMA CNTL1 bits 5–8 are **excluded** as primary cause (see ownership doc).

---

## Core question (hardware bridge)

`STAT1=0x4` proves the ACP block **generated the internal SDW1 event**.

Open question:

> **What hardware path converts `ACP_EXTERNAL_INTR_STAT1` into a legacy PCI IRQ edge that IO-APIC and Linux count?**

That path is where investigation effort should concentrate (~40% IO-APIC/GSI, ~30% ACP interrupt controller, ~20% firmware/BIOS, ~8% ps-common, ~2% manager — orientational only).

---

## Register map (IRQ block)

| Offset | Symbol | Role |
|--------|--------|------|
| `0x1241A00` | `ACP_EXTERNAL_INTR_ENB` | Global external interrupt enable |
| `0x1241A04` | `ACP_EXTERNAL_INTR_CNTL` | STAT0 unmask |
| `0x1241A08` | `ACP_EXTERNAL_INTR_CNTL1` | STAT1 unmask |
| `0x1241A0C` | `ACP_EXTERNAL_INTR_STAT` | STAT0 pending (W1C) |
| `0x1241A10` | `ACP_EXTERNAL_INTR_STAT1` | STAT1 pending (W1C) |

Sources: `acp63.h`, `linux-source-7.0.0/sound/soc/amd/ps/`.

---

## Milestone comparison (summary table)

Values from **p8-boundary-c1** resume and **journal `-b 0`** boot unless noted.

| Register / step | Boot @ first SDW1 IRQ | Resume @ post_delay (~51 ms) | Boot path? | Resume path? | Asymmetry |
|-----------------|----------------------|------------------------------|:----------:|:------------:|-----------|
| `INTR_ENB` | `1` | `1` (@ pm_resume_done) | ✓ init | ✓ init | — |
| `INTR_CNTL0` | `0x20000000` (ERROR) | `0x20010000` (ERROR + ?) | ✓ init | ✓ init | **C?** high nibble |
| `INTR_CNTL1` bit 2 (SDW1) | `0x4` | `0x400004` (bit 2 + bit 22) | ✓ manager | ✓ manager | **C** extra host-wake on resume |
| `STAT1` bit 2 | `0x4` pending | `0x4` pending | ✓ | ✓ | — |
| `STAT1` clear before unmask | implicit via **reset** in init | **never** in ps/ | ✓ reset | ✗ | **A** |
| `CNTL1` zero on deinit | N/A (cold) | **never** cleared in disable | — | ✗ | **A** |
| `ZSC_DSP_CTRL` | `0` @ init | `0` @ init | ✓ | ✓ | — |
| `PME_EN` | `1` | `1` | ✓ | ✓ | — |
| `pci_set_master()` | ✓ probe | ✗ | ✓ | ✗ | **A** |
| `request_irq()` | ✓ probe | ✗ | ✓ | ✗ | **A** |
| Linux `/proc/interrupts` | increments | **delta=0** (8.1) | ✓ | ✗ | **Fact** |
| `acp63_irq_handler()` | runs | **since_pm=0** (8.1) | ✓ | ✗ | **Fact** |
| `ps-sdw-dma` CNTL1 DMA bits | later (PCM) | not before STAT | ✓ later | ✗ | **exonerated** |

---

## Boot — ordered register writes (IRQ-relevant)

Path: `snd_acp63_probe()` → `acp70_init()` → (later) manager probe → first IRQ.

| # | Phase | Function | Register | Value / op | File |
|---|-------|----------|----------|------------|------|
| 1 | PCI | `pci_enable_device()` | PCI config | enable | `pci-ps.c` |
| 2 | PCI | `pci_set_master()` | PCI COMMAND | bus master | `pci-ps.c` |
| 3 | Init | `acp70_power_on()` | `ACP_PGFSM_*` | conditional | `ps-common.c` |
| 4 | Init | `acp70_init()` | `ACP_CONTROL` | `0x01` | `ps-common.c` |
| 5 | Init | `acp70_reset()` | `ACP_SOFT_RESET` | `1` → poll → `0` | `ps-common.c` |
| 6 | Init | `acp70_init()` | `ACP_ZSC_DSP_CTRL` | `0` | `ps-common.c` |
| 7 | Init | `acp70_enable_interrupts()` | `ACP_EXTERNAL_INTR_ENB` | `1` | `ps-common.c` |
| 8 | Init | `acp70_enable_interrupts()` | `ACP_EXTERNAL_INTR_CNTL` | `ACP_ERROR_IRQ` (`0x20000000`) | `ps-common.c` |
| 9 | Init | `acp70_enable_sdw_host_wake_interrupts()` *if* `SW*_WAKE_EN` | `ACP_EXTERNAL_INTR_CNTL1` | `\|= 0xC00000` | `ps-common.c` |
| 10 | Init | `acp70_init()` | `ACP_PME_EN` | `1` | `ps-common.c` |
| 11 | PCI | `devm_request_threaded_irq()` | Linux IRQ desc | register handler | `pci-ps.c` |
| 12 | Manager probe | `amd_enable_sdw_interrupts()` | `ACP_EXTERNAL_INTR_CNTL1` | `\|= 0x4` (SDW1) | `amd_manager.c` |
| 13 | Manager probe | `amd_enable_sdw_interrupts()` | `ACP_SW_STATE_CHANGE_STATUS_MASK_*` | IRQ masks | `amd_manager.c` |
| 14 | Manager probe | `amd_enable_sdw_manager()` | `ACP_SW_EN` | ENABLE | `amd_manager.c` |
| 15 | Event | HW → `STAT1` | `ACP_EXTERNAL_INTR_STAT1` | `0x4` | — |
| 16 | IRQ | `acp63_irq_handler()` | `ACP_EXTERNAL_INTR_STAT1` | W1C ack `ACP_SDW1_STAT` | `pci-ps.c` |

**Observed boot @ first IRQ (`journalctl -k -b 0`):** `request_irq irq=160` → manager `cntl_after=0x4` → `irq_handler_enter cntl1=0x4 stat1=0x4` → ATTACHED. **No PCM yet** — CNTL1 DMA bits appear only after `hw_params`.

---

## Resume — ordered register writes (IRQ-relevant)

Path: manager suspend → PCI suspend → PCI resume → manager resume → STAT pending.

### Suspend (children before parent)

| # | Phase | Function | Register | Value / op | File |
|---|-------|----------|----------|------------|------|
| S1 | Manager | `amd_disable_sdw_interrupts()` | `ACP_EXTERNAL_INTR_CNTL1` | clear manager mask bit | `amd_manager.c` |
| S2 | Manager | `amd_disable_sdw_manager()` | `ACP_SW_EN` | DISABLE | `amd_manager.c` |
| S3 | Manager | `amd_sdw_set_device_state()` | `AMD_SDW_DEVICE_STATE` | D3 | `amd_manager.c` |
| S4 | PCI | `snd_acp70_suspend()` samples | `ACP_SW0_EN \| ACP_SW1_EN` | → `sdw_en_stat=0` (after S2) | `ps-common.c` |
| S5 | PCI | `acp70_deinit()` | `ACP_EXTERNAL_INTR_STAT` | `0xFFFFFFFF` (**STAT0 only**) | `ps-common.c` |
| S6 | PCI | `acp70_disable_interrupts()` | `ACP_EXTERNAL_INTR_CNTL` | `0` | `ps-common.c` |
| S7 | PCI | `acp70_disable_interrupts()` | `ACP_EXTERNAL_INTR_ENB` | `0` | `ps-common.c` |
| S8 | PCI | `acp70_deinit()` | `ACP_SOFT_RESET` | reset cycle | `ps-common.c` |
| S9 | PCI | `acp70_deinit()` | `ACP_ZSC_DSP_CTRL` | `1` | `ps-common.c` |

**Not done on suspend deinit:** clear `INTR_STAT1`, clear/zero `INTR_CNTL1`.

### Resume (parent before children) — p8-boundary-c1 (full init)

| # | Phase | Function | Register | Value / op | File |
|---|-------|----------|----------|------------|------|
| R1 | PCI | `acp70_init()` | same as boot #3–10 | ENB, CNTL0, host_wake, PME | `ps-common.c` |
| R2 | PCI | *(none)* | — | **no** `request_irq` | — |
| R3 | PCI | *(none)* | — | **no** `pci_set_master` | — |
| R4 | Manager | `amd_enable_sdw_interrupts()` | `ACP_EXTERNAL_INTR_CNTL1` | `\|= 0x4` → **`0x400004`** | `amd_manager.c` |
| R5 | Manager | bring-up / D0 | `ACP_SW_EN`, device state | ENABLE, D0 | `amd_manager.c` |
| R6 | HW | ~51 ms later | `ACP_EXTERNAL_INTR_STAT1` | **`0x4`** | — |
| R7 | *(missing)* | — | Linux IRQ / handler | **not invoked** | 8.1 |

**Logged resume sequence (p8):**

```text
pm_resume_enter
cntl1_write who=acp70_host_wake  old=0x0 new=0xc00000
pm_resume_done  stat1=0x0 cntl1=0xc00000 enb=0x1
manager_reset → amd_enable_sdw_interrupts → CNTL1=0x400004
post_delay  STAT1=0x4  STAT&mask=0x4
/proc/interrupts delta=0 · handler_since_pm=0
```

---

## Asymmetry inventory (A / B / C / D)

### A — Boot only (resume never)

| Item | Detail | Priority |
|------|--------|----------|
| `pci_set_master()` | Probe only; never replayed on system resume | High |
| `devm_request_threaded_irq()` | Probe only; descriptor persists but line state unknown | High |
| Clean `INTR_STAT1` / `CNTL1` via **hardware reset** before first unmask | Cold init after reset; resume deinit **does not** clear STAT1/CNTL1 | Medium |
| `STAT1` W1C ack via handler before manager reprograms | Handler runs on boot; never on resume=1 | Medium |

### B — Resume only (boot never at same milestone)

| Item | Detail | Priority |
|------|--------|----------|
| Full `acp70_deinit()` immediately before init | Boot is cold; resume cycles disable→reset→init | Medium |
| `CNTL1 \|= 0xC00000` **before** manager mask on resume | Logged `acp70_host_wake` then manager `0x400004` | Low (boot can also set host_wake if `WAKE_EN`) |
| Manager `power_off` suspend mode | D3 + SW disable before PCI deinit | Context only |

### C — Same register, different value

| Register | Boot @ delivery | Resume @ delivery attempt | Assessment |
|----------|-----------------|---------------------------|------------|
| `INTR_CNTL1` | `0x4` | `0x400004` | Resume has **strict superset** of unmask bits; unlikely “missing unmask” |
| `INTR_CNTL0` | `0x20000000` | `0x20010000` @ post_delay | Needs register bit decode; not yet tied to delivery |

### D — Same value, different order

| Sequence element | Boot | Resume |
|------------------|------|--------|
| `request_irq` vs manager `CNTL1` bit 2 | **IRQ registered before** manager unmask | Manager unmask **without** re-`request_irq` |
| `enable_interrupts` vs manager | Init → **request_irq** → (later) manager | Init → manager (same ENB/CNTL0, no second IRQ register) |
| First `STAT1=0x4` vs handler | STAT → **IRQ immediately** | STAT → **no IRQ** (same bit) |

---

## `sdw_en_stat` fast path (alternate resume — not p8 run)

If `ACP_SW0_EN \| ACP_SW1_EN` non-zero at **suspend entry**:

| | Suspend | Resume |
|---|---------|--------|
| INTR block | **skipped** (no disable) | **skipped** (no enable) |
| Writes | `ZSC_DSP_CTRL=1` | `ZSC=0`, `PME=1` only |

p8 took **full init** (`acp70_host_wake` logged) → `sdw_en_stat==false` at suspend (manager disabled `SW_EN` first).

---

## Checklist — IRQ delivery preconditions

| # | Condition | Boot | Resume (p8) |
|---|-----------|:----:|:-----------:|
| 1 | `INTR_ENB == 1` | ✓ | ✓ |
| 2 | `CNTL1` SDW1 bit unmasked | ✓ (`0x4`) | ✓ (`0x400004`) |
| 3 | `STAT1` SDW1 pending | ✓ | ✓ @ +51 ms |
| 4 | Legacy line → IO-APIC counts edge | ✓ | **✗** (delta=0) |
| 5 | `request_irq` handler live | ✓ | ✓ (same desc, never re-run) |

**Gap:** row **#4** with #1–3 true.

---

## Maintainer question (concrete)

> During system resume on ACP70 we consistently observe `ACP_EXTERNAL_INTR_STAT1 = ACP_SDW1_STAT` about 50 ms after manager reset, but the shared legacy interrupt never reaches `acp63_irq_handler()` and `/proc/interrupts` does not increment. On cold boot the same status bit immediately results in IRQ delivery. Is there any ACP70-specific interrupt re-arm, bridge, or platform sequence outside `acp70_enable_interrupts()` that is required after s2idle resume?

Attach: [0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md), this matrix, [UPSTREAM-GIT-ACP70-PM.md](UPSTREAM-GIT-ACP70-PM.md).

---

## Next steps (no new experiments unless diff found)

1. Bit-level decode of `INTR_CNTL0=0x20010000` on resume vs boot.
2. Compare ACP6.3 vs ACP70 PM in upstream for STAT1/CNTL1 clear on deinit.
3. PCI PM: whether `pci_set_master` or IRQ re-enable is driver responsibility after s2idle.
4. If matrix complete with no software gap → upstream with bounded question above.

---

## Related

| Doc | Role |
|-----|------|
| [ACP-IRQ-REGISTER-OWNERSHIP.md](ACP-IRQ-REGISTER-OWNERSHIP.md) | Writers, PM order, facts vs open |
| [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) | Call map + delivery diagram |
| [UPSTREAM-GIT-ACP70-PM.md](UPSTREAM-GIT-ACP70-PM.md) | Upstream commit archaeology |
| [INDEX.md](INDEX.md) | Phase 8 roadmap |
