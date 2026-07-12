# Q3 — SoundWire re-attach: first missing state transition

English (canonical). **Branch B** (root cause). **Branch A (make it work):** [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md) — **P0 for daily work.**

> **Methodology:** state-based investigation. Document each transition as **observed** or **inferred**. Do **not** assume the break is at `manager_reset` until instrumentation shows it.

**Witness:** [../experiments/q2-fw-trace-witness-20260712.md](../experiments/q2-fw-trace-witness-20260712.md)  
**Q3 witness:** [../experiments/q3-sdw-reattach-witness-20260712.md](../experiments/q3-sdw-reattach-witness-20260712.md)  
**Model:** [../UNIFIED-CAUSAL-MODEL.md](../UNIFIED-CAUSAL-MODEL.md)

*(Directory name `q2.5-sdw-reattach` is historical; the open question is **Q3 / Q3.1** below.)*

---

## Question tree (symptom → state layers)

```text
Q1   hw_params returns -EINVAL                          [closed ~100%]
  ↓
Q2   because firmware async never started               [closed ~90–95% this cycle]
  ↓
Q2.5 because tas_io_init() never ran                   [closed this cycle — status != ATTACHED]
  ↓
Q3   re-attach does not complete                       [partial — bounded this cycle]
  ↓
Q3.1 where between STAT1=0x4 and ATTACHED?             [OPEN — active P0]
```

**Q3:** no ATTACHED observed post `manager_reset`; codec/FW chain follows.

**Q3.1:** bisect C1–C5 — [Q3.1-IRQ-CHECKPOINTS.md](Q3.1-IRQ-CHECKPOINTS.md).

Do **not** write “IRQ handler never executed” — only **not observed** until C1 (+ optional Phase 8.1 counters).

---

## Demonstrated for this cycle (codec / slave driver layer)

```text
resume → manager_reset → UNATTACHED
   ↓
status != ATTACHED                    [observed]
   ↓
skip_io_init                          [observed]
   ↓
no request_firmware_nowait()          [observed]
   ↓
hw_params wait timeout → -EINVAL      [observed — Q1]
```

**Consequence:** failure is **before** `tas_update_status(ATTACHED)` → search SoundWire re-attach, not TAS2783 FW logic.

---

## Q3.1 — STAT1=0x4 → ATTACHED (active)

```text
C1  ACP irq_handler_enter
C2  WAKE_THREAD / HANDLED sdw1
C3  amd irq_thread_enter
C4  handle_status
C5  state_change(ATTACHED)
```

Q3.1 C1 **closed** (c1-test): delivery gap before ACP handler — see [../experiments/q3.1-c1-boundary-witness-20260712.md](../experiments/q3.1-c1-boundary-witness-20260712.md).

**Next P0 (Branch A):** trial **0006a** workaround — [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md) W1.

Full protocol: [Q3.1-IRQ-CHECKPOINTS.md](Q3.1-IRQ-CHECKPOINTS.md)

---

## Candidate break models (non-exclusive)

### Model A — init timeout (-110)

Symptom observed; not proven as *first* break.

### Model B — enumeration does not reach ATTACHED

**Observed:** no `state_change new=ATTACHED` post-reset.  
**Not proven:** stall vs never started — Q3.1 checkpoints decide.

### Model C — ATTACHED without codec callback

No evidence this cycle.

---

## Correlated observation — bus alive, slave init incomplete

| Observation | Label |
|-------------|--------|
| `initialization timed out (-110)` | observed |
| `master_port OK`, `sdw_program_params OK` | observed |

**Inference:** master can program bus; slave init protocol does not reach ATTACHED / init complete.

---

## Investigation maturity

| Layer | Status |
|-------|--------|
| Q1 | ~100% closed |
| Q2 | ~90–95% closed |
| Q2.5 (layer) | Closed — `status != ATTACHED` |
| **Q3** | **Partial** — re-attach bounded |
| **Q3.1** | **Active** — C1–C5 bisect |

---

## What not to do

| Avoid | Reason |
|-------|--------|
| More TAS2783 FW as primary fix | Q2 closed |
| Assume `manager_reset` is root cause | Expected step |
| “Handler never ran” from log absence | Epistemic rule — use C1 + 8.1 |
| Treat 0003 as main fix | Requires ATTACHED |
| 0006a as product fix | Causal experiment only |

---

## Collect + analyze

```bash
systemctl suspend && sleep 5
./scripts/q3-sdw-reattach-collect.sh --label after-resume
./scripts/q3-sdw-reattach-analyze.sh
```

Build: `./scripts/build-q3-trace.sh` → reboot.

Analyzer: `[OBSERVED]` / `[NOT_OBS]` + Q3.1 checkpoint block. `NOT_OBS` ≠ proof of non-execution.

---

## Definition of done (Q3 / Q3.1)

| Gate | Criterion |
|------|-----------|
| Q3 | Re-attach bounded; no ATTACHED post-reset (same boot as Q2) |
| Q3.1 | First C1–C5 **not observed** with probe coverage; or 0006a causal |
| Fix | ATTACHED + PCM2 PASS without reboot |
| Upstream | “Not observed” vs “did not execute” distinguished |

---

## Related

| Doc | Role |
|-----|------|
| [Q3.1-IRQ-CHECKPOINTS.md](Q3.1-IRQ-CHECKPOINTS.md) | Active Q3.1 protocol |
| [../q2-fw-resume/CONSOLIDATION.md](../q2-fw-resume/CONSOLIDATION.md) | Q2 handoff |
| [../phase-6/KNOWN-FACTS.md](../phase-6/KNOWN-FACTS.md) | IRQ facts — correlate |
| [../phase-7/experiments/0006a-validate-manager-mask.md](../phase-7/experiments/0006a-validate-manager-mask.md) | Causal retest |
| [../frozen/upstream-proof/README.md](../frozen/upstream-proof/README.md) | Phase 6–8 |
