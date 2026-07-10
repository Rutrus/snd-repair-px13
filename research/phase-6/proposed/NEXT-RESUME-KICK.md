# Proposed 0007 — Resume kick sequence (not more register dumps)

English (canonical). After run **0014** (0006).

## Question

> After `INTR_CNTL`, `SDW_EN`, and `CLK_FRAME` look correct, **which driver calls should make the hardware raise the first `ACP_EXTERNAL_INTR_STAT` bit?**

## Code finding (AMD vs Intel)

Intel has explicit `start_bus_after_reset()` (`sdw_cdns_clock_restart`, `config_update`, …).

**AMD has no equivalent.** On `POWER_OFF` resume the driver runs:

```text
clk_resume (optional)
  → sdw_clear_slave_status        (software only)
  → amd_init_sdw_manager          (bus reset; ends with manager disabled)
  → amd_enable_sdw_interrupts
  → amd_enable_sdw_manager        (EN_STATUS=1)
  → amd_sdw_set_frameshape
  → amd_sdw_set_device_state(D0)  (ACP70 only — after 0006 snapshot)
```

The **first ping** (`amd_sdw_read_and_process_ping_status`) is only called from:

1. `amd_sdw_irq_thread` when `AMD_SDW_PREQ_INTR_STAT` is set (hardware PREQ), or
2. `amd_sdw_update_slave_status_work` after device0 is already ATTACHED (enumeration loop).

So the **first expected event is hardware-autonomous**: slave state change on the bus → `ACP_SW_STATE_CHANGE_STATUS_*` → ACP external IRQ → `acp63_irq_handler` → `amd_sdw_irq_thread`.

There is no `start_ping()` on the resume path.

## 0007 probes (existence only)

| Probe | Meaning |
|-------|---------|
| `clk_resume_done` / `clk_resume_skip` | Clock domain wake before reset |
| `clear_slave_status` | Bus layer UNATTACH tagging |
| `init_sdw_manager ret=` | Bus reset sequence result |
| `enable_sdw_manager ret=` | Manager enable poll |
| `frameshape_done` | Frame program complete |
| `device_state_D0 val=` | ACP70 power domain (runs **after** 0006 bringup reads) |
| `intr_stat_post_D0` | STAT after final resume step |

## Interpretation matrix

| Outcome | Meaning |
|---------|---------|
| All kicks `ret=0`, `intr_stat_post_D0=0`, no handler | Strong evidence: full software sequence ran; HW/firmware did not assert first event |
| `init_sdw_manager ret≠0` or `enable_sdw_manager ret≠0` | Sequencing failure before kick |
| `device_state_D0` missing on FAIL | ACP70 path not reached |
| `intr_stat_post_D0≠0` but no handler | S2 revisit (routing after D0) |
| PASS: same kicks, `intr_stat_post_D0≠0` | Timing or ordering hypothesis |

Patch: `0007-phase6-resume-kick-trace.patch` (on 0006).

**Status (run 0015):** complete on FAIL — all kicks `ret=0`, `STAT=0` post-D0. **Do not extend** with 0008 horizontal probes unless PASS/FAIL diff opens a new question. See [../UPSTREAM-CONTRAST.md](../UPSTREAM-CONTRAST.md).
