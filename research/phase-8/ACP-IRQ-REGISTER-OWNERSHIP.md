# ACP70 IRQ register ownership — static audit (`sound/soc/amd/ps/`)

English (canonical). Phase **8.2** audit. **Register matrix (boot vs resume):** [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md). **Call matrix (Rama A):** [ACP-BOOT-VS-RESUME-CALLS.md](ACP-BOOT-VS-RESUME-CALLS.md).

**Facts frozen in:** [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) (commit `48437e1`).

**Scope:** `ps-common.c`, `pci-ps.c`, `ps-sdw-dma.c`, `acp63.h` only.

**Policy:** No new printk experiments unless a concrete asymmetry from the register matrix warrants a single-variable test.

---

## Facts (demonstrated — cite upstream)

| Fact | Source |
|------|--------|
| `STAT1 & manager_mask = 0x4` ~51 ms after manager resume | Phase 7 correlate, p8-boundary-c1 |
| `/proc/interrupts` delta=0 on IRQ 160 after s2idle | p8-boundary-c1 (8.1) |
| `acp63_irq_handler()` not invoked since suspend (`handler_since_pm=0`) | p8-boundary-c1 (8.1) |
| Boot first SDW1 IRQ at **`CNTL1=0x4` only** (no DMA bits) | journal `-b 0` |
| Resume post_delay **`CNTL1=0x400004`** with same STAT, no IRQ | p8-boundary-c1 |
| `schedule_work(amd_sdw_irq_thread)` restores full downstream | Phase 7 0006a |
| Manager suspends before PCI; `SW_EN` cleared → full `acp70_deinit` on p8 | PM order + logs |
| `acp70_disable_interrupts()` clears **STAT0** only; never **STAT1** / **CNTL1** | code read |
| `request_irq` and `pci_set_master` **probe only** | code read — see [ACP-BOOT-VS-RESUME-CALLS.md](ACP-BOOT-VS-RESUME-CALLS.md) |
| **`ACP_SDW1_STAT` ack only in `acp63_irq_handler()`** | full-tree grep — not consumed on resume without handler |

---

## Open (working — not demonstrated)

| Item | Type | Notes |
|------|------|-------|
| Why legacy line does not pulse despite ENB=1 and STAT1 pending | **Primary gap** | Fits IO-APIC / bridge / firmware |
| Whether STAT1 should be cleared before unmask on resume | Code asymmetry **A** | Boot gets implicit reset |
| Whether `pci_set_master` must be replayed after s2idle | Code asymmetry **A** | Never on resume |
| `INTR_CNTL0=0x20010000` vs boot `0x20000000` significance | **C** | Bit decode pending |
| Fast path (`sdw_en_stat`) behaviour on other machines | Unknown | p8 used full init |
| BIOS/firmware erratum on PX13 | Unknown | After software matrix complete |

**Effort orientation (not measured):** ~40% IO-APIC/GSI, ~30% ACP interrupt controller, ~20% firmware, ~8% ps-common, ~2% manager.

---

## Closed question — DMA CNTL1 bits vs manager IRQ (2026-07-11)

**Question:** Does the first boot SDW1 IRQ occur before `ps-sdw-dma.c` sets CNTL1 bits 5–8?

**Answer: YES — DMA bits are not required for manager IRQ delivery.**

Evidence from **same boot** as p8-boundary-c1 (`journalctl -k -b 0`):

```text
17:11:24  request_irq irq=160
17:11:24  amd_manager cntl_write mask=0x4 cntl_after=0x4
17:11:24  irq_handler_enter cntl1=0x4 stat1=0x4  → sdw1_irq HANDLED
17:11:24  RT721 ATTACHED
          (no PCM / no hw_params yet)

… later boot …
17:11:27  irq_handler_enter cntl1=0x44   (DMA bits appearing)
17:11:27  irq_handler_enter cntl1=0x1c4
17:16:45  irq_handler_enter cntl1=0x1e4  (full DMA mask set)
```

**Fact:** First successful manager IRQ uses **`CNTL1=0x4` only** — identical manager mask bit to resume (`0x400004 & ~0x400000 = 0x4`).

**Fact:** Resume post_delay had **`CNTL1=0x400004`** (manager bit 2 **plus** host-wake bit 22) with **`STAT1=0x4`** but **no IRQ** (8.1).

**Conclusion (fact-backed):** Bits 5–8 (`ps-sdw-dma` watermark unmask) are **not** prerequisites for SDW1 manager legacy IRQ. The boot vs resume `0x1e4` vs `0x400004` comparison is **misleading** for delivery failure — focus shifts to legacy line / ACP PM restore (`ps-common.c`, `pci-ps.c`) or hardware after s2idle.

---

## `ps-sdw-dma.c` — what it writes (code read)

| When | Function | Registers | Manager coupling |
|------|----------|-----------|------------------|
| PCM `hw_params` | `acp63_sdw_dma_hw_params()` | `CNTL*` \|= per-stream DMA bit; watermark size reg | **None** — no manager calls |
| System resume (PCM platform) | `acp63_sdw_pcm_resume()` → `acp70_restore_sdw_dma_config()` | bulk `CNTL*` DMA masks if active substreams | **None** |

Pattern is `configure ring → set watermark → OR dma bit into CNTL` — **not** `enable_dma → enable_manager`.

---

## Entry condition (handler perspective)

For `acp63_irq_handler()` to run:

1. **Legacy PCI IRQ line** must assert → IO-APIC counts edge → Linux `generic_handle_irq`.
2. **`request_irq()`** already registered handler at **probe** (not re-run on system resume).
3. Handler **reads** `ACP_EXTERNAL_INTR_STAT*`; it does **not** unmask — masking is in `CNTL*`.

8.1 proved step 1 fails on resume while `STAT1` bit 2 is set. Audit question:

> Which `writel()` to ACP IRQ registers happens on **boot** but never on **resume**, or at a **different time / hardware state**?

---

## Register map (ACP6.3/7.0 block)

| Offset (byte) | Symbol | Role |
|---------------|--------|------|
| `0x1241A00` | `ACP_EXTERNAL_INTR_ENB` | Global external interrupt enable |
| `0x1241A04` | `ACP_EXTERNAL_INTR_CNTL` | STAT0 unmask / control |
| `0x1241A08` | `ACP_EXTERNAL_INTR_CNTL1` | STAT1 unmask / control |
| `0x1241A0C` | `ACP_EXTERNAL_INTR_STAT` | STAT0 pending (W1C via write same bit) |
| `0x1241A10` | `ACP_EXTERNAL_INTR_STAT1` | STAT1 pending (W1C) |
| `0x1241A4C` | `ACP_ERROR_STATUS` | Error detail (cleared in handler) |

Related (not INTR block, but PM path): `ACP_PME_EN`, `ACP_SW0/1_WAKE_EN`, `ACP_ZSC_DSP_CTRL`, `ACP_SW0/1_EN`.

---

## CNTL1 bit ownership (hypothesis driver)

Constants from `acp63.h` (ACP70 SDW1 path):

| Bit | Mask | Meaning | Programmed by (ps/ tree) |
|-----|------|---------|---------------------------|
| 2 | `0x4` | **SDW1 manager IRQ** (`ACP_SDW1_STAT`) | **Not in ps/** — `amd_enable_sdw_interrupts()` via `acp_mmio` |
| 3 | `0x8` | SDW1 audio2 RX DMA threshold | `ps-sdw-dma.c` `acp63_enable_disable_sdw_dma_interrupts()` |
| 5 | `0x20` | SDW1 audio1 RX DMA threshold | `ps-sdw-dma.c` |
| 6 | `0x40` | SDW1 audio1 TX DMA threshold | `ps-sdw-dma.c` |
| 7 | `0x80` | SDW1 audio0 RX DMA threshold | `ps-sdw-dma.c` |
| 8 | `0x100` | SDW1 audio0 TX DMA threshold | `ps-sdw-dma.c` |
| 22–23 | `0xC00000` | **SDW host-wake unmask** (`ACP70_SDW_HOST_WAKE_MASK`) | `ps-common.c` `acp70_enable_sdw_host_wake_interrupts()` |
| 23 | `0x800000` | SDW1 host wake (manager header) | Also `amd_sdw_host_wake_enable()` (soundwire, not ps/) |

**Observed values (PX13, link 1):**

| When | CNTL1 | Notes |
|------|-------|-------|
| Boot **first** `sdw1_irq` @ 17:11:24 | **`0x4`** | Manager mask only — **IRQ delivered** |
| Boot later (PCM active) | `0x44` → `0x1c4` → `0x1e4` | DMA bits added **after** first manager IRQ |
| Resume @ post_delay | **`0x400004`** | bit 2 + bit 22 — **IRQ not delivered** (8.1) |

~~**8.2 question:** Who builds **`0x1e4` on boot** and why does resume never restore bits 5–8?~~ **Closed:** `0x1e4` is post-PCM; first delivery uses `0x4` only. Not the resume failure cause.

---

## Register writers (ps/ only)

| Register | Writer function | File | Boot | System resume |
|----------|-----------------|------|------|---------------|
| `INTR_ENB` ← 1 | `acp63/70_enable_interrupts()` | ps-common | `acp*_init` (probe) | `acp70_init` **if full path**; **skip** if `sdw_en_stat` fast |
| `INTR_ENB` ← 0 | `acp*_disable_interrupts()` | ps-common | deinit / remove | deinit **if** `!sdw_en_stat` on suspend |
| `INTR_CNTL0` ← `ACP_ERROR_IRQ` | `acp*_enable_interrupts()` | ps-common | init | full init only |
| `INTR_CNTL0` ← 0 | `acp*_disable_interrupts()` | ps-common | deinit | full deinit suspend |
| `INTR_CNTL1` \|= host wake | `acp70_enable_sdw_host_wake_interrupts()` | ps-common | init (if `SW*_WAKE_EN`) | full init only |
| `INTR_CNTL1` \|= DMA masks | `acp63_enable_disable_sdw_dma_interrupts()` | ps-sdw-dma | **stream open** (hw_params) | **not in PM resume** |
| `INTR_CNTL1` \|= DMA (per-stream) | `acp_sdw_dma_enable()` path | ps-sdw-dma | playback/capture | same — tied to ASoC, not `snd_acp70_resume` |
| `INTR_STAT*` (ack) | `acp63_irq_handler()`, wake helpers | pci-ps | runtime | runtime (never reached resume=1) |
| `PME_EN` ← 1 | `acp70_init()`, fast resume | ps-common | init | **both** paths |
| `ZSC_DSP_CTRL` | suspend/resume fast path | ps-common | — | fast: 1→0 |
| `SW0/1_WAKE_EN` ← 0 | `check_and_handle_acp70_sdw_wake_irq()` | pci-ps | wake events | wake events |

**Outside ps/ but same MMIO:** `amd_enable_sdw_interrupts()` sets CNTL1 bit 2 (`mask=0x4`). Documented here for **`0x400004`** timeline only.

---

## Boot vs resume — `writel()` graph (ACP PCI path)

### Boot (cold)

```text
snd_acp63_probe()
  pci_set_master()
  acp_hw_init() → acp70_init()
      acp70_power_on / reset
      acp70_enable_interrupts()
          INTR_ENB = 1
          INTR_CNTL0 = BIT(29) error
          [optional] acp70_enable_sdw_host_wake → CNTL1 |= 0xC00000
      PME_EN = 1
  devm_request_threaded_irq(..., acp63_irq_handler)   ← once
  … platform devs / machine …
  (later, on audio use)
  ps-sdw-dma: CNTL1 |= DMA bits → contributes to 0x1e4
  (later, manager probe)
  amd_enable_sdw_interrupts: CNTL1 |= bit 2
```

### System resume (s2idle)

```text
snd_acp_suspend()
  acp_hw_suspend() → snd_acp70_suspend()
      if sdw_en_stat: ZSC_DSP=1; return     ← no disable_interrupts
      else: acp70_deinit() → disable INTR*

snd_acp_resume()
  acp_hw_resume() → snd_acp70_resume()
      if sdw_en_stat: ZSC=0; PME=1; return  ← NO enable_interrupts, NO init
      else: acp70_init() → enable_interrupts + host_wake + PME

(no request_irq)
(no ps-sdw-dma CNTL1 restore unless PCM re-triggers)
(manager resume runs separately — CNTL1 bit 2)
```

### Writel in boot path but absent on typical resume

| Action | Boot | Resume (sdw_en_stat fast) | Resume (full init, p8 run) |
|--------|------|---------------------------|----------------------------|
| `pci_set_master()` | ✓ probe | ✗ | ✗ |
| `request_irq()` | ✓ probe | ✗ | ✗ |
| `acp70_enable_interrupts()` | ✓ | ✗ | ✓ |
| `ps-sdw-dma` CNTL1 DMA bits | ✓ (on stream use) | ✗ before STAT | ✗ before STAT |
| `acp70_disable_interrupts()` on suspend | if `!sdw_en_stat` | ✗ | ✗ |

p8-boundary-c1 took **full init** (host_wake logged) and still **no IRQ**. DMA CNTL1 bits **exonerated** (boot delivers at `0x4`). Remaining ps/ focus:

1. **No second `request_irq`** — descriptor exists; line state after s2idle unknown.
2. **Resume `0x400004` vs boot first `0x4`** — resume has **extra** host-wake bit 22, not missing manager bit.
3. **Suspend fast path** — `sdw_en_stat` may skip `disable_interrupts` / `enable_interrupts`; half-latched INTR block vs clean boot.

---

## `sdw_en_stat` fork (order matters)

Sampled at **suspend entry** from `ACP_SW0_EN | ACP_SW1_EN`:

| | Suspend | Resume |
|---|---------|--------|
| `sdw_en_stat == true` | `ZSC_DSP=1` only | `ZSC=0`, `PME=1` only |
| `sdw_en_stat == false` | full `acp70_deinit()` | full `acp70_init()` |

**Check on next code pass:** log or infer `sdw_en_stat` on p8 run. If SW links were enabled at suspend, full init at resume would **contradict** fast-path logic — host_wake log implies **`sdw_en_stat == false`** at suspend (or full deinit path taken).

---

## Working backwards checklist

| # | Condition for handler entry | Verified boot | Verified resume |
|---|----------------------------|---------------|-----------------|
| 1 | `INTR_ENB == 1` | ✓ (logs) | ✓ @ pm_resume_done |
| 2 | `CNTL1` bit 2 unmasked | ✓ (`0x4` @ first IRQ) | ✓ (`0x400004`) |
| 3 | `STAT1` bit 2 pending | ✓ | ✓ @ +51 ms |
| 4 | Legacy IRQ edge to IO-APIC | ✓ (`/proc/interrupts`++) | ✗ (delta=0) |
| 5 | `request_irq` handler registered | ✓ probe | ✓ (same desc) |

Gap is **#4** with #1–3 true → PM sequence audit below; if no software gap → firmware / legacy line.

---

## PM flow audit — `acp70_init` vs `snd_acp70_{suspend,resume}`

Source: `ps-common.c`, `pci-ps.c`. **Working notes** — register touches only.

### Execution graph — system resume

```text
snd_acp_resume()                         pci-ps.c
  └── acp_hw_resume()
        └── snd_acp70_resume()           ps-common.c
              │
              ├── sdw_en_stat == true    (sampled at suspend from SW0_EN|SW1_EN)
              │     writel ZSC_DSP_CTRL = 0
              │     writel PME_EN = 1
              │     return 0             ← NO acp70_init, NO enable_interrupts
              │
              └── sdw_en_stat == false
                    acp_hw_init() → acp70_init()
                          PGFSM power-on (maybe)
                          CONTROL = 1
                          SOFT_RESET 1→poll→0→poll
                          ZSC_DSP_CTRL = 0
                          acp70_enable_interrupts()
                                INTR_ENB = 1
                                INTR_CNTL0 = ERROR (bit 29)
                                [if SW*_WAKE_EN] CNTL1 |= 0xC00000
                          PME_EN = 1
                    [optional] PAD_KEEPER / PULLDOWN restore
                    return

(no request_irq — already registered at probe)
(manager resumes later as child platform device)
```

### Execution graph — cold probe (IRQ-relevant tail)

```text
snd_acp63_probe()
  pci_enable_device()
  pci_set_master()                       ← probe only
  acp_hw_init() → acp70_init()           ← same register sequence as resume full path
  devm_request_threaded_irq(...)         ← probe only
  create platform devs → amd_manager probe (later)
        amd_enable_sdw_interrupts()        ← CNTL1 bit 2 (outside ps/)
```

### System suspend graph

```text
snd_acp_suspend() → acp_hw_suspend() → snd_acp70_suspend()
  if is_sdw_dev:
      save PAD_KEEPER, PULLDOWN
      sdw_en_stat = SW0_EN | SW1_EN
      if sdw_en_stat:
          ZSC_DSP_CTRL = 1
          return 0                       ← NO acp70_deinit
  acp_hw_deinit() → acp70_deinit()
      acp70_disable_interrupts()
            writel STAT0 = all-1s clear   ← STAT1 NOT touched
            INTR_CNTL0 = 0                  ← CNTL1 NOT touched
            INTR_ENB = 0
      SOFT_RESET + ZSC_DSP_CTRL = 1
```

---

## Probe vs resume — register operations

| Operation | Registers touched | Probe (boot) | Resume fast (`sdw_en_stat`) | Resume full (`!sdw_en_stat`, p8 run) |
|-----------|-------------------|:------------:|:---------------------------:|:------------------------------------:|
| PCI bus master | PCI config | ✓ `pci_set_master` | ✗ | ✗ |
| PGFSM power-on | `ACP_PGFSM_*` | ✓ init | ✗ | ✓ init |
| ACP reset | `ACP_SOFT_RESET`, `ACP_CONTROL` | ✓ init | ✗ | ✓ init |
| Global INTR enable | `INTR_ENB=1` | ✓ init | ✗ | ✓ init |
| Error unmask | `INTR_CNTL0` | ✓ init | ✗ | ✓ init |
| Host-wake unmask | `INTR_CNTL1` \|= `0xC00000` | ✓ if `WAKE_EN` | ✗ | ✓ if `WAKE_EN` |
| Clear pending STAT0 | `INTR_STAT` write | ✓ **deinit only** | ✗ | ✓ deinit on prior suspend |
| Clear pending STAT1 | `INTR_STAT1` | **never in ps/** | ✗ | ✗ |
| Clear / zero CNTL1 | `INTR_CNTL1` | **never in ps/** | ✗ | ✗ (persists through deinit) |
| ZSC DSP | `ZSC_DSP_CTRL` | 0 @ init | 0 @ resume | 0 @ init |
| PME | `PME_EN=1` | ✓ init | ✓ fast resume | ✓ init |
| Register IRQ handler | Linux `request_irq` | ✓ probe | ✗ | ✗ |
| Manager SDW1 unmask | `CNTL1` bit 2 | later (manager) | later | later |

---

## Sequence asymmetries (code facts, not hypotheses)

### 1. `acp70_disable_interrupts()` incomplete vs SDW1 path

```c
writel(ALL_1s, INTR_STAT);      /* STAT0 only */
writel(0, INTR_CNTL0);          /* CNTL1 unchanged */
writel(0, INTR_ENB);
```

**Fact:** **`INTR_STAT1` and `INTR_CNTL1` are never cleared** in ps/ disable or init. Boot reaches first IRQ with `CNTL1=0x4` after **hardware reset** in `acp70_init`. Resume full path runs init **without** clearing STAT1/CNTL1 first — stale manager mask bits may remain until manager reprograms.

### 2. Fast path (`sdw_en_stat`) skips entire INTR block

If `SW0_EN|SW1_EN` non-zero at **suspend entry**, neither `acp70_disable_interrupts()` nor `acp70_enable_interrupts()` runs across s2idle. Only `ZSC_DSP_CTRL` 1↔0 and `PME_EN` on resume.

**Fact:** p8-boundary-c1 logged `acp70_host_wake` → **full init path** on that cycle → likely `sdw_en_stat==false` at suspend (e.g. manager already disabled SW before PCI suspend — PM ordering).

### 3. `enable_interrupts` order inside `acp70_init`

```text
reset complete → ZSC=0 → ENB/CNTL0/[CNTL1 host_wake] → PME=1
```

**Never:** clear STAT1 before unmask. **Never:** `request_irq` again.

### 4. Boot-only PCI / Linux steps

| Step | Probe | Any resume path |
|------|-------|-----------------|
| `pci_set_master` | ✓ | ✗ |
| `devm_request_threaded_irq` | ✓ | ✗ |
| `pci_enable_device` | ✓ | ✗ (device stays enabled) |

---

## Resolved hypotheses (Phase 8 inventory)

| Hypothesis | Status |
|------------|--------|
| SoundWire manager broken | ✗ closed (Phase 7) |
| Downstream `irq_thread → ATTACHED` | ✗ closed (0006a experiment) |
| RT721 primary cause | ✗ closed |
| DMA CNTL1 bits 5–8 required for manager IRQ | ✗ closed (boot @ `CNTL1=0x4`) |
| `STAT1=0x4` pending on resume | ✓ fact |
| Linux never receives IRQ on resume | ✓ fact (8.1) |
| Missing `acp70_enable_interrupts()` always | ✗ (p8 full init still fails) |
| **Legacy line not pulsing after s2idle** | **open** — fits all facts |
| **PM sequence / STAT1·CNTL1 not reset** | **open** — code asymmetry above |
| **BIOS / firmware / erratum** | **open** — if software table complete |

---

---

## Device hierarchy and PM order (vertical audit)

### Device tree (probe)

```text
PCI: snd-pci-ps (AMD ACP)                    pci-ps.c probe
  parent = NULL
  request_irq(ACP_PCI_IRQ)                     ← only here
  │
  ├── platform: amd_sdw_manager.{0,1}        amd_init.c sdw_amd_probe_controller
  │     parent = &pci->dev                     pdevinfo.parent = res->parent
  │     mmio = manager window; acp_mmio = shared ACP base
  │     dev_pm: SET_SYSTEM_SLEEP_PM_OPS(amd_suspend, amd_resume_runtime)
  │     │
  │     └── sdw bus + slaves (rt721, tas2783, …)   ACPI/SDW core
  │
  ├── platform: amd_ps_sdw_dma                 pci-ps.c create_acp63_platform_devs
  │     parent = &pci->dev
  │
  └── platform: machine (acp_ps_mach / SDW mach)
        parent = &pci->dev
```

**No `device_link`**, **no `component` master** between PCI ACP and manager — ordering comes from **parent/child** only (`platform_device_register_full(... parent = pci->dev)`).

Shared serialization: `acp_lock` / `acp_sdw_lock` passed into manager pdata (MMIO races avoided, not PM order).

---

### Kernel PM rule (parent/child)

| Phase | Order |
|-------|--------|
| **Suspend** | Children **before** parent |
| **Resume** | Parent **before** children |

Source: Linux driver model — platform devices are children of `pci->dev`.

---

### Suspend sequence (PX13, p8 run + code)

**Journal @ s2idle** (`journalctl -k -b 0`, 17:17:57):

```text
1. rt721 resume_enter (fast)          ← amd_pm_prepare resumes runtime-suspended children
2. tas2783 / rt721 system_suspend
3. PHASE8 pm_suspend_enter (PCI ACP) ← parent, last in audio subtree
```

Manager `amd_suspend` has **no PHASE6 log**, but runs as **child before PCI** (DPM + parent/child).

**`amd_suspend()` side effects** (`power_off` mode, p8 `mode=power_off` on resume):

```text
amd_disable_sdw_interrupts()     → CNTL* manager mask cleared (amd_updatel)
amd_deinit_sdw_manager()           → SW_EN disabled (ACP_SW_EN)
amd_sdw_set_device_state(D3)       → AMD_SDW_DEVICE_STATE
amd_sdw_host_wake_enable(false)    → CNTL1 host-wake bits cleared (earlier in path)
```

**Then PCI `snd_acp70_suspend()`:**

```text
sdw_en_stat = SW0_EN | SW1_EN     → 0 after manager deinit
→ acp70_deinit()                   → disable INTR (STAT0 only), ENB=0, reset
```

**Fact (code + order):** Manager **disables `SW_EN` before** PCI samples `sdw_en_stat`. p8 **full `acp70_init` on resume** is explained — not speculation.

---

### Resume sequence (PX13, p8 run — verified)

```text
1. PHASE7 pm_resume_enter (PCI ACP)
2. acp70_init → enable_interrupts → CNTL1 host_wake 0xc00000
3. PHASE7 pm_resume_done  ENB=1  stat1=0  cntl1=0xc00000
4. PHASE6 amd fn=resume_enter  system_resume  power_off
5. manager_reset → amd_enable_sdw_interrupts → CNTL1=0x400004
6. post_delay STAT1=0x4  →  no handler  (8.1)
```

**Effective owner of INTR block when manager starts resume:** PCI driver already wrote **ENB, CNTL0, host_wake CNTL1**. Manager then owns **CNTL1 bit 2** + SW-side masks. **`request_irq` not re-run.**

---

## Register ownership graph

```text
                    ┌─────────────────────────────────────┐
                    │     ACP MMIO (shared acp63_base)     │
                    └─────────────────────────────────────┘
         │                              │
   PCI ps-common                   amd_sdw_manager
   (ACP PCI driver)                (platform child)
         │                              │
   INTR_ENB                         CNTL1 bit 2 (SDW1 mask)
   INTR_CNTL0 (error)               SW_STATE_CHANGE_STATUS_MASK*
   CNTL1 host_wake 0xC00000         AMD_SDW_DEVICE_STATE D0/D3
   disable: STAT0 clear only        SW_EN enable/disable
   (never STAT1/CNTL1 clear)        amd_disable_sdw_interrupts on suspend
         │                              │
         └──────── acp_sdw_lock ────────┘

   Linux IRQ: PCI probe only ──→ acp63_irq_handler
   (never re-registered on resume)
```

| Register / concern | Owner at runtime | Suspend last writer (typical) | Resume first writer |
|--------------------|------------------|-------------------------------|---------------------|
| `INTR_ENB` | PCI `acp70_enable/disable` | PCI deinit (after manager) | PCI init |
| `INTR_CNTL0` | PCI | PCI deinit | PCI init |
| `INTR_CNTL1` bit 2 | Manager | Manager disable (clears mask) | Manager enable |
| `INTR_CNTL1` host wake | PCI (+ manager host_wake_enable) | Both may clear | PCI init, then manager |
| `INTR_STAT1` | HW + handler ack | **Nobody clears** | — |
| `ACP_SW_EN` | Manager | Manager deinit | Manager enable |
| Legacy IRQ desc | PCI `request_irq` | (unchanged) | (unchanged) |

---

## STAT1 changes but no IRQ (narrowed)

Boot and resume both reach **`CNTL1` bit 2 set + `STAT1=0x4`**. Boot @ `CNTL1=0x4` delivers IRQ; resume @ `0x400004` does not.

**Remaining explanations (ACP domain):**

1. Legacy IRQ line / INTR block not re-armed after s2idle (despite ENB=1).
2. **`pci_set_master` / PCI IRQ routing** not replayed on resume.
3. Missing **STAT1 clear + re-enable** sequence that boot reset implicitly provides.
4. Firmware / silicon behaviour after s2idle.

**Excluded:** SoundWire manager logic, RT721, DMA CNTL1 bits 5–8.

---

## Maintainer-ready statement (draft, when audit complete)

> We compared ACP70 cold probe with system resume. Device PM order: `amd_sdw_manager` (child) suspends before PCI ACP; PCI resumes before manager. On suspend, manager deinit clears `SW_EN` so PCI takes full `acp70_deinit`. On resume, PCI runs `acp70_init` then manager sets `CNTL1=0x400004`. Hardware sets `STAT1=0x4` ~51 ms later; `/proc/interrupts` unchanged and handler never entered (8.1). Boot delivers IRQ with the same manager mask (`CNTL1=0x4`). ps/ never clears `INTR_STAT1`; resume does not call `request_irq` or `pci_set_master`. Either a missing legacy-IRQ restore step exists in ACP PCI PM, or delivery fails at hardware/firmware after s2idle.

---

## Next code-read (PM focus)

1. **`acp70_disable_interrupts`** — should STAT1/CNTL1 be cleared? Compare Intel/Other AMD ACP drivers.
2. **`pci_set_master`** after s2idle — PCI PM core vs driver responsibility.
3. **Document PM order** in upstream question (child-before-parent suspend) — maintainers may know required handshake between PCI and manager resume.
4. If no software gap → upstream with statement above.

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md) | 8.1 frozen facts |
| [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) | Call map + last-write timeline |
| [INDEX.md](INDEX.md) | Phase 8 roadmap |
