# Q3 — SoundWire re-attach: first missing state transition

English (canonical). **Active P0** after Q2 witness (2026-07-12).

> **Methodology:** state-based investigation. Document each transition as **observed** or **inferred**. Do **not** assume the break is at `manager_reset` until instrumentation shows it.

**Witness:** [../experiments/q2-fw-trace-witness-20260712.md](../experiments/q2-fw-trace-witness-20260712.md)  
**Model:** [../UNIFIED-CAUSAL-MODEL.md](../UNIFIED-CAUSAL-MODEL.md)

*(Directory name `q2.5-sdw-reattach` is historical; the open question is **Q3** in the question tree below.)*

---

## Question tree (symptom → state layers)

```text
Q1   hw_params returns -EINVAL                          [closed ~100%]
  ↓
Q2   because firmware async never started               [closed ~90–95% this cycle]
  ↓
Q2.5 because tas_io_init() never ran                   [closed this cycle — status != ATTACHED]
  ↓
Q3   which is the first SoundWire re-attach transition  [OPEN — active P0]
     that does not occur after resume?
```

**Q3 binary question:**

> **What is the first transition in the SoundWire re-attach flow that does not occur after resume?**

**Answer for 2026-07-12 cycle (~85–90%):** AMD **IRQ worker / handle_status** path after `manager_reset` — STAT1 latched, no re-attach. Witness: [../experiments/q3-sdw-reattach-witness-20260712.md](../experiments/q3-sdw-reattach-witness-20260712.md).

Not: “why does `manager_reset` fail?” — that would pre-judge the break site.

---

## Demonstrated for this cycle (codec / slave driver layer)

```text
resume
   ↓
status != ATTACHED                    [observed]
   ↓
skip_io_init                          [observed]
   ↓
no request_firmware_nowait()          [observed]
   ↓
fw_dl_task_done == false              [observed]
   ↓
hw_params wait timeout                [observed]
   ↓
-EINVAL                               [observed — Q1]
```

**Consequence:** the failure is **before** a successful `tas_update_status()` path that would call `tas_io_init()` on **ATTACHED**. That bounds search to SoundWire re-attach, not TAS2783 FW logic.

---

## Re-attach ladder (locate first missing transition)

Instrument **one boot** and mark each step `[observed OK]` / `[observed FAIL]` / `[not seen]`:

```text
PM resume
    ↓
amd_sdw_manager resume
    ↓
manager_reset                         [observed on suspend — not proven as break site]
    ↓
enumeration
    ↓
slave ATTACHED
    ↓
tas_update_status()
    ↓
tas_io_init()
    ↓
request_firmware_nowait()
    ↓
tas2783_fw_ready()
```

Q3 success = identify the **first** step that does not occur (or completes with error) on a failing resume.

---

## Not yet demonstrated — candidate break models

Do not treat these as exclusive; instrumentation must choose.

### Model A — `initialization_complete` never succeeds

```text
resume → … → wait initialization_complete → timeout (-110)
```

**Observed on this cycle:** `resume: initialization timed out`, `PM failed to resume: -110`.  
**Not proven:** that this is the *first* break (vs a symptom of a later stall).

### Model B — enumeration does not reach ATTACHED

```text
manager_reset → enumeration → status stays UNATTACHED
```

**Observed:** `status=0`, `manager_reset` on suspend; **no** `state_change new=ATTACHED` post-reset (2026-07-12 Q3 witness).  
**Not proven:** whether enumeration started and stalled vs never invoked — IRQ worker absent supports stall/non-delivery hypothesis.

### Model C — slave enumerated but `tas_update_status(ATTACHED)` never called

Would imply a **different** bug class (core/driver callback path).  
**Not observed** in current trace — no ATTACHED transition logged for `:8`/`:b` post-resume.

---

## Correlated observation — bus alive, slave init incomplete

Same boot shows **both**:

| Observation | Label |
|-------------|--------|
| `resume: initialization timed out (-110)` | observed |
| `master_port OK`, `sdw_program_params OK` (ENZODBG / port programming) | observed |

**Strong inference (maintainer-useful):** the SoundWire **master** can still program the bus after resume, but the **slave initialization protocol** does not reach the expected logical state (`ATTACHED` / init complete).

**Not claimed:** physical link failure. Points to init/sync/protocol after resume rather than a dead bus.

---

## Instrumentation target (SoundWire manager / core — not TAS2783)

Find who produces:

```text
UNATTACHED  →  ATTACHED
```

Suggested probe sites:

| Function | Layer |
|----------|--------|
| `amd_resume()` | AMD manager |
| `amd_sdw_irq_thread()` | AMD IRQ worker |
| `sdw_handle_slave_status()` | SoundWire core |
| `sdw_initialize_slave()` | SoundWire core |
| `sdw_update_slave_status()` | SoundWire core |
| `tas_update_status()` | Codec slave (confirm ATTACHED never delivered) |

Goal: **complete timeline** on one suspend/resume cycle.

---

## Investigation maturity (engineering estimate)

| Layer | Status |
|-------|--------|
| Q1 | ~100% closed |
| Q2 | ~90–95% closed — FW never starts this cycle; origin of absence bounded to pre-`io_init` |
| Q2.5 (layer) | Closed this cycle — `io_init` skipped because `status != ATTACHED` |
| **Q3** | **Active** — first missing re-attach transition |

---

## What not to do

| Avoid | Reason |
|-------|--------|
| More TAS2783 FW patches as primary fix | Q2 closed at codec ladder |
| Assume `manager_reset` is root cause | Break site not localized |
| Claim “AMD manager bug” without first-fail step | Inference discipline |
| Treat 0003 as PX13 main fix | Requires ATTACHED |

---

## Suggested capture (one boot)

```bash
journalctl -k -b 0 | grep -E 'initialization timed|master_port|sdw_program|ATTACHED|UNATTACHED|PHASE6|manager_reset|amd_sdw'
```

Archive under `validation/q3-sdw-reattach/`.

### Collect + analyze (preferred)

```bash
# Kernel: PHASE6 + Q2 (or ./scripts/build-q3-trace.sh)
systemctl suspend && sleep 5
./scripts/q3-sdw-reattach-collect.sh --label after-resume
./scripts/q3-sdw-reattach-analyze.sh
```

Or one-shot build: `./scripts/build-q3-trace.sh` → reboot → suspend → collect/analyze.

The analyzer prints `[OK]` / `[MISSING]` per ladder step and hints at the **first missing transition** (does not assume `manager_reset` is the break site).

Legacy Phase 6 workflow: `./scripts/phase6-experiment.sh`, `./scripts/phase6-resume-timeline.sh`

---

## Definition of done (Q3)

| Gate | Criterion |
|------|-----------|
| Localized | First transition in re-attach ladder marked `[FAIL]` or `[missing]` on same boot as Q2 witness pattern |
| Or fix | ATTACHED returns; PCM2 hw_params PASS without reboot |
| Upstream | Timeline with observed/inferred labels; bus-alive + init-timeout correlation if reproduced |

---

## Related

| Doc | Role |
|-----|------|
| [../q2-fw-resume/CONSOLIDATION.md](../q2-fw-resume/CONSOLIDATION.md) | Q2 handoff |
| [../phase-6/KNOWN-FACTS.md](../phase-6/KNOWN-FACTS.md) | IRQ candidate — correlate, don’t assume |
| [../frozen/upstream-proof/README.md](../frozen/upstream-proof/README.md) | Phase 6–8 |
