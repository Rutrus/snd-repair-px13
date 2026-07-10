# Proposed 0006 — ACP block state snapshot (not scattered trace)

English (canonical). After run **0013**. Replaces ad-hoc probe list in earlier draft.

**Single question:**

> **Is the hardware actually prepared to generate the first post-reset event?**

**Do not instrument:** RT721, TAS2783, SoundWire bus, userspace. Those layers have served their role.

---

## Structured read sequence (one resume, one log block)

Log once per system resume (`resume=N`), immediately after existing `irq_enabled` / `intr_stat_post_enable` (0005), **after** `amd_enable_sdw_manager()` and frameshape if they run on this path:

```text
resume_enter          (0003)
    ↓
manager_reset         (0003)
    ↓
irq_enabled           (0004)
    ↓
intr_cntl_post_enable read ACP_EXTERNAL_INTR_CNTL(instance)
    ↓
intr_stat_post_enable read ACP_EXTERNAL_INTR_STAT(instance)   (0005)
    ↓
sdw_en_post_resume    read ACP_SW_EN / ACP_SW_EN_STATUS (or equivalent)
    ↓
(optional) clk_frame   clock resume + frameshape status if already on path
```

Uniform log line:

```text
PHASE6 ctx=amd fn=<name> link=%d resume=%d val=0x%x
```

**Not** a register dump — one `val=` per named probe.

---

## Interpretation (FAIL vs PASS)

Compare the **same snapshot** on PASS when captured:

| Field | FAIL (0013) | PASS (expected) |
|-------|-------------|-----------------|
| CNTL mask | TBD | likely non-zero / enabled bits |
| STAT | **0** | **≠0** (or rises before handler) |
| SDW enable | TBD | block enabled |

If PASS shows identical CNTL + enable but STAT≠0 only on PASS → timing/kick hypothesis. If FAIL shows enable=0 or CNTL wrong → sequencing bug in driver resume path.

---

## Scope rules

- ACP / `amd_manager.c` only for 0006 (reads already use `acp_mmio` / manager `mmio`).
- No new `bus.c`, `ping_status`, codec PM.
- No behaviour-changing fixes until FAIL vs PASS snapshot differs.

Patch file: create `0006-phase6-acp-block-state.patch` when implementing (applies on 0005).

Build: extend `scripts/build-phase6-amd-trace.sh`.

---

## Remaining work (~5% of investigation)

1. **0006** — why STAT=0 on FAIL (block prepared or not).
2. **PASS** — clean-boot capture with 0003–0005 (0006 optional) for maintainer table above.
