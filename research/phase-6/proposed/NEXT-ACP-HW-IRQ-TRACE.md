# Next ACP hardware IRQ trace (proposed 0005)

English (canonical). Applies on top of [0004-phase6-amd-minimal-irq-trace.patch](0004-phase6-amd-minimal-irq-trace.patch).

**Pivot (post run 0010):** `amd_enable_sdw_interrupts()` is **not** the break. Next question is not `ping_status` — it is whether a **hardware interrupt exists** and where it is lost.

---

## Binary question

> After `irq_enabled` on system resume (`resume=N`), does `ACP_EXTERNAL_INTR_STAT` show an SDW bit, does the PCI IRQ handler run, and does `amd_sdw_irq_thread` execute?

---

## Probe chain (four existence points)

```text
irq_enabled                    (0004 — done)
       ↓
intr_stat_post_enable          readl(ACP_EXTERNAL_INTR_STAT) once after enable (amd or pci-ps)
       ↓
acp_irq_handler_enter          acp63_irq_handler() first line (any ext_intr_stat)
       ↓
sdw0_irq                       ACP_SDW0_STAT branch (0004 — done)
       ↓
ping_irq                       amd_sdw_irq_thread entry (0004 — done)
```

Uniform log:

```text
PHASE6 ctx=<acp|amd> fn=<name> resume=%d [stat=0x%x]
```

Filter analysis by `resume=N` from system suspend only.

---

## Four scenarios (FAIL interpretation)

| # | Pattern | Layer |
|---|---------|-------|
| **S1** | `intr_stat_post_enable` never shows SDW bit (stays 0) | Hardware / firmware / ACP block not asserting |
| **S2** | STAT bit set, **no** `acp_irq_handler_enter` / `sdw0_irq` | IRQ routing (PCI, mask, IOMMU) |
| **S3** | `sdw0_irq` / handler, **no** `ping_irq` | `schedule_work(irq_thread)` / workqueue |
| **S4** | `ping_irq sc=0`, no `queue_work` | SDW protocol / empty status (was H2) |

Run 0010 is compatible with **S1 or S2** (no `sdw0_irq` at all).

---

## Suggested probe locations

| fn | File | When |
|----|------|------|
| `intr_stat_post_enable` | `amd_manager.c` after `amd_enable_sdw_interrupts()` | Log `readl(acp_mmio + ACP_EXTERNAL_INTR_STAT[instance])` + CNTL mask |
| `acp_irq_handler` | `pci-ps.c` `acp63_irq_handler` entry | Log `ext_intr_stat` before bit tests |
| `sdw0_irq` | `pci-ps.c` | *(0004)* |
| `ping_irq` | `amd_manager.c` | *(0004)* |

Optional: one-shot `mod_timer` or `readl_poll_timeout` in resume path **observation only** — only if STAT never changes in S1 and maintainers accept a poll probe (discuss before adding).

---

## PASS vs FAIL contrast (upstream target)

**PASS (expected):**

```text
manager_reset → irq_enabled → sdw0_irq → ping_irq → queue_work → ATTACHED → completion
```

**FAIL (0010):**

```text
manager_reset → irq_enabled → (silence) → wait_init_timeout
```

First divergence = maintainer-ready evidence. Requires **clean-boot PASS** (`resume=1`), not second suspend after broken state (run 0011 = FAIL-2 cascade).

---

## Do not add yet

- More `bus.c` / `ping_status` verbosity
- Behavior-changing IRQ fixes
- Codec or TAS2783 patches

Build: extend `scripts/build-phase6-amd-trace.sh` for 0005.
