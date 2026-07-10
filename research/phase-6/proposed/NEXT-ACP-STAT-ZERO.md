# Next ACP trace — why STAT stays 0 (proposed 0006)

English (canonical). After run **0013** (S1; S2 ruled out on that run).

**Do not add SoundWire / codec trace.** All value is in ACP70.

---

## Question

> Why does `ACP_EXTERNAL_INTR_STAT` read **0** immediately after `manager_reset` + `irq_enabled` on FAIL?

`STAT=0` does not name the mechanism — only that no pending interrupt is visible at the probe point.

---

## Candidate probes (minimal, existence or single register read)

| # | Question | Suggested probe |
|---|----------|-----------------|
| 1 | Was `ACP_EXTERNAL_INTR_CNTL` written correctly? | Log mask written in `amd_enable_sdw_interrupts()` |
| 2 | Is the SDW manager block enabled after resume? | `ACP_SW_EN` / enable status reg post-`amd_enable_sdw_manager()` |
| 3 | Does HW expect a kick (first PING / clock / frameshape) before STAT can rise? | Log whether `amd_enable_sdw_manager` / frameshape ran before STAT read |
| 4 | Power / clock gating | `AMD_SDW_DEVICE_STATE` or clk resume bits already on path — log final state |

Pick **one or two** per iteration; avoid register dumps every resume.

---

## What we are not doing

- More `bus.c`, `ping_status`, RT721, TAS2783
- Behavior-changing “fix” patches until PASS/FAIL mechanism differs

---

## PASS value

```text
FAIL 0013:  irq_enabled → STAT=0 → no handler
PASS (goal): irq_enabled → STAT≠0 → irq_handler_enter → … → completion
```

That diff is sufficient for an upstream report once PASS is captured with 0005 instrumentation.
