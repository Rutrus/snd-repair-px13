# Next AMD trace — minimal IRQ chain (proposed 0004)

English (canonical). Replaces verbose status/mask logging in [0003-phase6-amd-sdw-trace.patch](0003-phase6-amd-sdw-trace.patch) for bisect.

---

## Goal

Answer one binary question per system resume (`resume=N`):

> Did step X run after `manager_reset`?

---

## Four probe points only

```text
resume_enter     (amd_resume_runtime entry — exists in 0003)
       ↓
irq_enabled      (after amd_enable_sdw_interrupts in POWER_OFF resume path)
       ↓
ping_irq         (pci-ps ACP_SDW0_STAT → schedule_work(irq_thread)
                  OR amd_sdw_irq_thread first line with non-zero status regs)
       ↓
queue_work       (schedule_work(amd_sdw_work) in irq_thread)
```

Log format (uniform):

```text
PHASE6 ctx=amd fn=<name> link=%d resume=%d
```

No `devmask`, no `st0..3`, no `resp=0x…` in this patch — add back only if chain reaches queue_work but bus stays dead.

---

## Expected outcomes

| Pattern | Interpretation |
|---------|------------------|
| `resume_enter` → `irq_enabled` → *(nothing)* | **H1** — IRQ not delivered or not scheduled |
| → `ping_irq` → *(no queue_work)* | **H2** — irq_thread early exit / empty status |
| → `queue_work` → no bus ATTACHED | **H3** — worker/handle or empty status[] |
| → bus ATTACHED + completion | **PASS / Case D** |

---

## Files

| File | Change |
|------|--------|
| `drivers/soundwire/amd_manager.c` | `fn=irq_enabled` after interrupt enable on system resume path |
| `drivers/soundwire/amd_manager.c` | `fn=ping_irq` at `amd_sdw_irq_thread` entry (or PREQ/ping branch) |
| `drivers/soundwire/amd_manager.c` | simplify `fn=queue_work` (drop masks) |
| `sound/soc/amd/ps/pci-ps.c` | optional `fn=sdw_irq_stat` when `ACP_SDW0_STAT` schedules irq_thread |

Build: extend `scripts/build-phase6-amd-trace.sh` or add `build-phase6-acp-irq-trace.sh` for `snd-pci-ps.ko` if pci-ps probe added.

---

## FAIL-1 vs FAIL-2

Both classes show `manager_reset`. Trace must filter by `resume=N` from system suspend only (`resume=0` = runtime PM noise).

FAIL-2 (run 0007) may show reset without RT721 wait — still valid for AMD chain bisect.

---

## IO_PAGE_FAULT

If `ping_irq` never fires, add correlated log in same window:

```bash
journalctl -k -b 0 --since … --until … | grep -E 'IO_PAGE_FAULT|ACP_SDW'
```

Do not assert causality until PASS/FAIL table is filled.
