# Q3 SoundWire re-attach witness — 2026-07-12

**Machine:** ASUS ProArt PX13, kernel `7.0.0-27-generic`  
**Boot:** same session as [q2-fw-trace-witness-20260712.md](q2-fw-trace-witness-20260712.md)  
**Collect:** `validation/q3-sdw-reattach/after-resume-20260712T110525.log` (also 103319 capture)  
**Modules:** PHASE6 (0002–0007) + PHASE7 ACP trace + TAS2783Q2

---

## Question (Q3)

What is the **first transition** in the SoundWire re-attach ladder that does not occur after resume?

**Q3.1 follow-up:** [../q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md](../q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md)

---

## Demonstrated (observed facts, this cycle)

```text
resume → manager_reset → UNATTACHED
    → (no ATTACHED observed)
    → tas_io_init not observed → nowait not observed → fw_ready not observed
    → hw_params wait → timeout → -EINVAL
```

| Observation | Label |
|-------------|--------|
| AMD `resume_enter` + `manager_reset` + D0 bring-up ret=0 | observed |
| `state_change` ATTACHED→UNATTACHED (all slaves) | observed |
| PHASE7 `intr_decode post_delay` STAT1=0x4 | observed (register read) |
| `state_change` → ATTACHED / `fn=completion` post-reset | **not observed** |
| PHASE6 `irq_thread_enter` / `handle_status` post-reset | **not observed** |
| PHASE7 `irq_handler_enter` post-reset | **not observed** |
| RT721/TAS2783 init timeout / PM -110 | observed |
| TAS2783 `status=0`, `skip_io_init` | observed |

---

## Resume timeline (post manager_reset)

| Time (local) | Marker | Label |
|--------------|--------|-------|
| 10:33:19.374 | `fn=manager_reset` resume=1 | observed |
| 10:33:19.375 | UNATTACHED detach ×3 | observed |
| 10:33:19.376–378 | init/irq/D0/intr_stat — ret=0 | observed |
| 10:33:19.379 | intr_decode STAT1=0x4 @ +51 ms | observed |
| 10:33:19.380+ | C1–C5 Q3.1 checkpoints | **not observed** |
| 10:33:19.381 | wait_init_timeout / PM -110 | observed |

---

## Contrast — S0 same boot (~10:29:56–57)

Runtime path (playback) shows full C1→C5 chain:

```text
irq_handler_enter → sdw1_irq → HANDLED
  → irq_thread_enter → ping_irq → handle_status
  → state_skip / state_change ALERT→ATTACHED
```

Same modules, same boot — chain **observed at runtime**, **not observed post system resume** after manager_reset.

---

## What we claim vs what we do not

| Claim | Status |
|-------|--------|
| ATTACHED never observed post-reset this cycle | **Fact** |
| STAT1=0x4 visible in manager register decode | **Fact** |
| End-to-end codec chain follows from missing ATTACHED | **Fact** (Q2/Q1) |
| “IRQ handler did not execute” | **Not claimed** — only **not observed** in PHASE7 trace; Phase 8.1 counters can strengthen |
| “Worker is the root cause” | **Not claimed** — 0006a causal retest pending on this boot lineage |

**Search focus (Q3.1):** break between STAT1=0x4 and ATTACHED — bisect C1→C5; do not assume C1.

---

## Definition of done — Q3 partial / Q3.1 open

| Gate | Status |
|------|--------|
| Q3: symptom bounded to re-attach | **Yes** |
| Q3.1: first checkpoint not observed | **C1** (pending 8.1 / 0006a) |
| Fix validated | No |

---

## Reproduce

```bash
./scripts/q3-sdw-reattach-collect.sh --label after-resume
./scripts/q3-sdw-reattach-analyze.sh
```

Requires `./scripts/build-q3-trace.sh`, reboot.
