# Experiment 0006a — validate manager interrupt mask (IRQ delivery)

English (canonical). **NOT a fix** — falsify whether the **driver-defined manager IRQ bit** ever appears on FAIL-1, and whether manually scheduling `amd_sdw_irq_thread` when it does would unblock enumeration.

**Prerequisite:** Phase 7 experiment 0005 showed delayed `STAT` change (`0→0x4`) without handler. **Do not** treat `0x4` as `ACP_SDW0_STAT` — see [0006b-stat-decode.md](0006b-stat-decode.md).

Patch: `research/phase-7/proposed/0006a-validate-manager-mask.patch` (TBD)

**Commit order:** land [0006b](0006b-stat-decode.md) (observation) **before** this patch. One binary question per commit.

---

## Context (post-0005)

Three distinct facts on FAIL-1 (d50, valid `resume=1`):

1. Resume kick sequence completes (`ret=0`, D0, enable, frameshape).
2. After ~50 ms, **a bit appears** in `ACP_EXTERNAL_INTR_STAT(instance)` (`0x4` on PX13).
3. `acp63_irq_handler` does **not** run — it tests `ACP_SDW0_STAT` (`BIT(21)` = `0x200000`) on `ACP_EXTERNAL_INTR_STAT`, not `0x4`.

**0006a does not explain what `0x4` is.** It only tests the bit the **driver itself** considers the valid manager external IRQ for this instance.

---

## Register model (verified in tree)

From `sound/soc/amd/ps/acp63.h`, `drivers/soundwire/amd_manager.h`, `sound/soc/amd/ps/pci-ps.c`:

| Symbol | Value | Register (ACP70) | Handler checks |
|--------|-------|------------------|----------------|
| `ACP_SDW0_STAT` | `BIT(21)` = `0x200000` | `ACP_EXTERNAL_INTR_STAT` (0x1A0C) | `ext_intr_stat & ACP_SDW0_STAT` |
| `ACP_SDW1_STAT` | `BIT(2)` = `0x4` | `ACP_EXTERNAL_INTR_STAT1` (0x1A10) | `ext_intr_stat1 & ACP_SDW1_STAT` |
| `AMD_SDW0_EXT_INTR_MASK` | `0x200000` | `ACP_EXTERNAL_INTR_CNTL(0)` | enabled by `amd_enable_sdw_interrupts` |
| `AMD_SDW1_EXT_INTR_MASK` | `4` | `ACP_EXTERNAL_INTR_CNTL(1)` | enabled by `amd_enable_sdw_interrupts` |

Per-instance macros in `amd_manager.h`:

```c
#define ACP_EXTERNAL_INTR_STAT(i)  (ACP_EXTERNAL_INTR_STAT0 + ((i) * 4))
#define ACP_EXTERNAL_INTR_CNTL(i)  (ACP_EXTERNAL_INTR_CNTL0 + ((i) * 4))
```

**PX13 (single manager):** expect `instance=0`, `link_id=1`. Manager mask = `0x200000`. Observed delayed `STAT=0x4` is **not** `stat & manager_mask` for instance 0.

**Open (0006b):** d50 logged `INTR_CNTL(0)=0x400004` (`BIT(22)|BIT(2)`) while `AMD_SDW0_EXT_INTR_MASK` is `0x200000` (`BIT(21)`). Decode before upstream claims.

---

## Hypothesis A (0006a)

> On FAIL-1, if the **manager mask bit** (`stat & AMD_SDW{0,1}_EXT_INTR_MASK`) becomes set, scheduling `amd_sdw_irq_thread` without a physical IRQ is sufficient to progress toward ATTACHED/completion.

## Hypothesis A-negative (publishable)

> On FAIL-1, **`stat & manager_mask` never becomes non-zero** during the RT721 wait window — the block never asserts the IRQ bit the driver expects, even when other STAT bits (e.g. `0x4`) appear later.

---

## Intervention (minimal)

After Phase 7 delay window (or fixed post-D0 poll — reuse `phase7_delay_ms` param or dedicated boot param):

```c
mask = sdw_manager_reg_mask_array[amd_manager->instance];
stat = readl(acp_mmio + ACP_EXTERNAL_INTR_STAT(amd_manager->instance));

/* log: instance, mask, stat, stat & mask */

if (stat & mask)
    schedule_work(&amd_manager->amd_sdw_irq_thread);
```

**Do not** trigger on `stat == 0x4` alone. **Do not** call `amd_sdw_read_and_process_ping_status()` in 0006a.

---

## Binary outcomes

| Outcome | Interpretation | Next |
|---------|----------------|------|
| `stat & mask` never set (FAIL-1) | Hardware/firmware never raises **expected** manager IRQ bit | Why CNTL vs STAT mismatch; 0006b decode; kick / ACPI |
| `stat & mask` set, manual `schedule_work`, no ATTACHED | Thread runs but status path empty — see 0006b / thread probes | 0006c or ping path |
| `stat & mask` set, manual `schedule_work`, ATTACHED/completion | **IRQ delivery** broken; HW path OK | Upstream: MSI/routing/`pci-ps.c` |
| `irq_handler_enter` without manual schedule | Physical IRQ works in this run — compare to FAIL baseline | Golden diff |

---

## Log probes (0006a)

```text
PHASE7 ctx=amd fn=stat_mask_check link=%d resume=%d instance=%u mask=0x%x stat=0x%x hit=%u
PHASE7 ctx=amd fn=manual_schedule_irq_thread link=%d resume=%d instance=%u stat=0x%x
```

Reuse Phase 6 chain after manual schedule: `irq_thread_enter`, `queue_work`, bus `ATTACHED`, `completion`.

---

## Run protocol

Same witness as Phase 6 / 0005:

```bash
./scripts/build-phase7.sh --experiment validate-manager-mask   # TBD script name
sudo reboot
./scripts/phase7-sweep-pre.sh 50    # or fixed delay via modprobe.d
# login → verify → post → suspend → --after-suspend
```

One suspend per boot (`resume_n=1`).

Optional control: `delay_ms=0` with 0006a patch only (no delay, poll once post-D0).

---

## Relation to 0006b / 0006c

| Exp | Question | Intervention |
|-----|----------|--------------|
| **0006a** (this) | Does **manager mask** bit ever hit? Does `schedule_work` on **mask hit** progress? | `stat & mask` → `schedule_work` only |
| [0006b](0006b-stat-decode.md) | What is `0x4`? CNTL vs STAT vs instance? | Observation-only decode |
| [0006c](0006c-force-schedule-stat4.md) | Can thread progress if forced on `stat==0x4`? | Deliberate hack — falsification only |

Run **0006b** (observation) before or in same patch as 0006a logging; run **0006c** only if 0006a is negative and 0006b shows persistent `0x4`.

---

## Build

TBD: extend `build-phase7.sh --experiment validate-manager-mask` on Phase 6 trace + optional 0005 delay param base.
