# ACP70 boot vs resume — function call matrix (Rama A)

English (canonical). Compare **call sequences**, not register values. Scope: `sound/soc/amd/ps/` + manager entry points only (manager internals excluded except where boot/resume diverge).

**Prerequisite:** [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) · register view: [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md)

**Policy:** No commit / no upstream mail until patch candidates below are tested or ruled out.

---

## Question (narrowed)

> What differs between the **first SDW1 legacy IRQ on cold boot** and the **first `STAT1=0x4` after s2idle resume** — in **function calls** through `ps/`?

Not: RT721, TAS, PipeWire, DMA watermarks, `schedule_work` as fix.

---

## End-to-end call comparison

### PCI ACP driver (`pci-ps.c`)

| Step | Cold boot (`snd_acp63_probe`) | System resume (`snd_acp_resume` → p8 full init) |
|------|-------------------------------|--------------------------------------------------|
| Entry | `snd_acp63_probe()` | `snd_acp_resume()` |
| PCI enable | `pci_enable_device()` | **—** (device stays enabled) |
| Regions / MMIO | `pci_request_regions()`, `devm_ioremap()` | **—** (mapped at probe) |
| Bus master | **`pci_set_master()`** | **—** |
| HW ops table | `acp_hw_init_ops()` | **—** (set at probe) |
| ACP init | `acp_hw_init()` → **`acp70_init()`** | `acp_hw_resume()` → **`snd_acp70_resume()`** → **`acp_hw_init()` → `acp70_init()`** |
| IRQ registration | **`devm_request_threaded_irq(..., acp63_irq_handler)`** | **—** |
| Platform children | `create_acp63_platform_devs()` → `sdw_amd_probe()` | **—** (devices persist) |
| Machine | `acp63_machine_register()` | **—** |
| Runtime PM setup | `pm_runtime_*`, `device_set_wakeup_enable()` | **—** |
| Pad restore | — | **`snd_acp70_resume()`** may restore `PAD_KEEPER` / `PULLDOWN` |

**Only-on-boot calls (type A):** `pci_set_master`, `devm_request_threaded_irq`, `pci_enable_device`, platform/machine registration.

**Resume-only calls (type B):** `snd_acp70_resume()` pad restore (conditional).

---

### Inside `acp70_init()` (same function, both paths)

| Order | Call | Boot | Resume (full path) |
|-------|------|:----:|:------------------:|
| 1 | `acp70_power_on()` | ✓ | ✓ |
| 2 | `writel(CONTROL, 1)` | ✓ | ✓ |
| 3 | `acp70_reset()` | ✓ | ✓ |
| 4 | `writel(ZSC_DSP_CTRL, 0)` | ✓ | ✓ |
| 5 | `acp70_enable_interrupts()` | ✓ | ✓ |
| 5a | → `writel(INTR_ENB, 1)` | ✓ | ✓ |
| 5b | → `writel(INTR_CNTL0, ERROR)` | ✓ | ✓ |
| 5c | → `acp70_enable_sdw_host_wake_interrupts()` *if* `SW*_WAKE_EN` | ✓ | ✓ (p8 logged) |
| 6 | `writel(PME_EN, 1)` | ✓ | ✓ |

**Same function, same order** on p8 run. No missing `enable_interrupts()` on full path.

---

### Suspend deinit (resume-only precursor)

Boot does **not** run this before first IRQ. Resume full path ran this on prior suspend:

| Call | `snd_acp70_suspend()` → `acp70_deinit()` |
|------|------------------------------------------|
| `acp70_disable_interrupts()` | clears **STAT0**, zeros CNTL0, ENB=0 — **not STAT1/CNTL1** |
| `acp70_reset()` | |
| `writel(ZSC_DSP_CTRL, 1)` | **no** `writel(CONTROL, 0)` (ACP63 deinit does) |

---

### SoundWire manager — first bring-up vs resume

| Step | Boot | System resume |
|------|------|---------------|
| Entry | `sdw_amd_probe()` → `sdw_amd_startup()` → **`amd_sdw_manager_start()`** | **`amd_resume_runtime()`** (via `SET_SYSTEM_SLEEP_PM_OPS(..., amd_resume_runtime)`) |
| Preconditions | After **`request_irq`** | After PCI **`acp70_init()`**; **no** second `request_irq` |
| Manager init | `amd_init_sdw_manager()` | `amd_init_sdw_manager()` (power_off path) |
| Unmask | `amd_enable_sdw_interrupts()` | `amd_enable_sdw_interrupts()` |
| Enable link | `amd_enable_sdw_manager()` | `amd_enable_sdw_manager()` |
| Frame | `amd_sdw_set_frameshape()` | `amd_sdw_set_frameshape()` |
| ACP70 D0 | (during start / probe) | `amd_sdw_set_device_state(D0)` |
| Extra resume steps | — | `sdw_clear_slave_status(MASTER_RESET)`, clk resume, `amd_sdw_host_wake_enable(false)` |

**Manager call set is parallel** for the IRQ-relevant tail (`init → enable_irq → enable_manager`). Difference is **PCI-side** steps before manager runs and **PM ordering** (parent resume before child).

---

### PM order (fact)

```text
Suspend:  manager amd_suspend  →  PCI snd_acp_suspend  →  acp70_deinit
Resume:   PCI snd_acp_resume   →  acp70_init           →  manager amd_resume_runtime
```

---

## First SDW1 IRQ milestone

| | Boot | Resume (p8) |
|---|------|-------------|
| `STAT1` | `0x4` | `0x4` @ ~51 ms |
| Next call expected | `acp63_irq_handler()` | `acp63_irq_handler()` |
| Actual | handler → ack → `schedule_work` | **handler never called** |
| Linux IRQ accounting | increments | **delta=0** (8.1) |

---

## STAT1 ACK audit (question 2)

**Does anything clear `ACP_SDW1_STAT` (manager bit, `0x4`) outside `acp63_irq_handler()`?**

**Answer: NO** — in the entire `linux-source-7.0.0` tree, `writel(..., ACP_EXTERNAL_INTR_STAT1)` for the manager path appears only in `pci-ps.c`:

| Function | When | Bits acked | Requires handler? |
|----------|------|------------|-------------------|
| **`acp63_irq_handler()`** | IRQ delivery | **`ACP_SDW1_STAT`** (`0x4`) | self |
| `check_and_handle_acp70_sdw_wake_irq()` | called **from handler only** | host-wake, PME bits | yes |
| `check_and_handle_sdw_dma_irq()` | called **from handler only** | DMA threshold bits on STAT1 | yes |

**`ps-common.c`:** `acp70_disable_interrupts()` clears **`ACP_EXTERNAL_INTR_STAT` (STAT0)** only — **never STAT1**.

**`amd_manager.c`:** no direct `writel` to `ACP_EXTERNAL_INTR_STAT1`.

### Consequence (strong)

On resume:

```text
STAT1=0x4 appears  →  nothing in software consumes it without handler
                   →  /proc/interrupts delta=0
                   →  bit stays pending (not silently acked elsewhere)
```

The event is **not eaten** by wake/DMA/deinit paths. Failure is **before** handler entry: **STAT latched in ACP MMIO, legacy line / IO-APIC / Linux IRQ layer never sees an edge**.

---

## ACP6.3 vs ACP70 code diff (`ps-common.c`)

Side-by-side read (same file, two hw_ops tables). IRQ-relevant differences:

| Area | ACP6.3 (`acp63_*`) | ACP70 (`acp70_*`) | Notes |
|------|-------------------|-------------------|-------|
| `enable_interrupts` | ENB + CNTL0 only | + **`acp70_enable_sdw_host_wake_interrupts()`** if `SW*_WAKE_EN` | ACP70-only CNTL1 `\|= 0xC00000` |
| `init` order | reset → **enable_irq** → ZSC=0 | reset → ZSC=0 → **enable_irq** → **PME=1** | Order swap + PME |
| `deinit` tail | reset → **CONTROL=0** → ZSC=1 | reset → ZSC=1 (**no CONTROL=0**) | Resume cycles through this deinit |
| `snd_*_resume` fast path | ZSC=0 only | ZSC=0 + **PME=1** | p8 used **full** init, not fast path |
| `runtime_resume` full path | `acp_hw_init` + **`handle_acp63_sdw_pme_event()`** | `acp_hw_init` only | ACP63-only PME event helper |
| STAT1 clear on disable | **never** | **never** | Same gap both revisions |

**Nothing removed on ACP70 port** that obviously “used to clear STAT1” — the gap exists on **both** revisions; ACP70 adds host-wake + PME in init.

---

## Asymmetry summary (calls, not registers)

| Type | Finding | Patch relevance |
|------|---------|-----------------|
| **A** | `pci_set_master()` probe-only | **High** — common resume omission |
| **A** | `request_irq()` probe-only | Medium — descriptor exists; line state unknown |
| **A** | `pci_enable_device()` probe-only | Low — usually OK across s2idle |
| **B** | Prior `acp70_deinit()` before init on resume | Context — boot never deinits first |
| **B** | `snd_acp70_resume()` pad restore | Low for IRQ |
| **D** | **`request_irq` before manager start** (boot) vs **init → manager without re-register** (resume) | **High** — ordering / re-arm |
| — | Manager `init→enable_irq→enable_manager` | **Same** calls |
| — | STAT1 ack only in handler | **Event not consumed** — bridge/line issue |

---

## Patch candidates (ranked — test before upstream)

Hypothesis-only. Each should be a **single-variable** local build test.

Investigator review (2026-07-11): deprioritize `pci_set_master`; **STAT1 clear before enable/unmask** is priority 1. See [INVESTIGATOR-QA.md](INVESTIGATOR-QA.md) — **pre-unmask STAT1=0 already proven** in runs 0014/0015/p8 (edge “stale STAT before unmask” variant ruled out).

| Rank | Change | Binary question | Notes |
|------|--------|-----------------|-------|
| **1** | W1C clear **`INTR_STAT1`** in `acp70_enable_interrupts()` after reset, before ENB/unmask | Restore IRQ delivery? | Causal link to handler-only ack |
| **2** | STAT1 clear immediately before manager CNTL1 bit-2 unmask | Same | Tests unmask instant |
| **3** | Extend `acp70_disable_interrupts()` → clear STAT1, zero CNTL1 | Symmetric deinit fixes resume? | Suspend leaves CNTL1 stale (code fact) |
| **4** | `writel(CONTROL, 0)` in `acp70_deinit()` (ACP63 parity) | Any effect? | Minor ACP63/70 diff |
| **5** | `pci_set_master()` in `snd_acp_resume()` | Falsify only | Weak; MMIO already works |

**Deprioritized:** manager changes, `schedule_work` hack, DMA bits, new delays.

**Suggested test order:** (1) → snapshot `/proc/interrupts` + one suspend cycle; if fail, (2) or (3) one at a time.

---

## If all candidates fail

Stop digging in ALSA tree. Upstream with:

- deterministic repro, 8.1 three witnesses, 0006a causal experiment,
- this call matrix + STAT1 ack proof,
- bounded question: missing **ACP70 interrupt re-arm / legacy bridge** after s2idle.

See [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) (Rama B — hold send).

---

## Related

| Doc | Role |
|-----|------|
| [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md) | Register-level matrix |
| [ACP-IRQ-REGISTER-OWNERSHIP.md](ACP-IRQ-REGISTER-OWNERSHIP.md) | Writers, PM order |
| [UPSTREAM-GIT-ACP70-PM.md](UPSTREAM-GIT-ACP70-PM.md) | Upstream commit context |
| [INDEX.md](INDEX.md) | Phase 8 roadmap |
