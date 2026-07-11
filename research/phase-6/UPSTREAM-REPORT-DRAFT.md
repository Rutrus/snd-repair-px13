# Upstream report draft — ACP70 SoundWire s2idle resume (PX13)

English (canonical). **Submittable** — causal boundary delimited through Phase 7 (0007 correlate).

Related: [KNOWN-FACTS.md](KNOWN-FACTS.md) · [../JOURNEY.md](../JOURNEY.md) · [../phase-7/experiments/0007-run-correlate-d50.md](../phase-7/experiments/0007-run-correlate-d50.md) · [../phase-7/experiments/0006a-run-p7-d50.md](../phase-7/experiments/0006a-run-p7-d50.md)

**Reading guide:** maintainers can start at [Facts](#facts-demonstrated), [Investigation tree](#investigation-tree), [Inference](#inference), and [Remaining questions](#remaining-questions).

Throughout this document:

- **Facts** — directly observed in kernel logs on repeated runs.
- **Inference** — reasonable conclusion from those facts; not independently proven.
- **Not demonstrated** — explicitly out of scope of current evidence.

---

## Executive summary

On ASUS ProArt PX13 (ACP70 + SoundWire), s2idle resume consistently fails with RT721 `-ETIMEDOUT` (`FAIL-1`).

**Facts:** After resume, the SoundWire manager observes `ACP_EXTERNAL_INTR_STAT1 & AMD_SDW1_EXT_INTR_MASK == 0x4` approximately 50 ms after D0, but `acp63_irq_handler()` is **not invoked** during the resume window. An experimental patch that calls `schedule_work(&amd_sdw_irq_thread)` when `stat & manager_mask` restores full SoundWire bring-up (ATTACHED → completion → RT721 success).

**Inference:** There is a gap between the interrupt status the manager reads and entry into the ACP platform IRQ handler on resume. The downstream SoundWire path appears functional once the worker thread runs.

---

## Investigation phase

| Phase | Status |
|-------|--------|
| **Delimitation** (where does it break?) | **Complete** — Phase 6 + Phase 7 (0005–0007) |
| **Fix** (restore handler entry after s2idle) | **Open** — Phase 8: ACP platform interrupt path |

---

## Hardware

| Component | Detail |
|-----------|--------|
| Machine | ASUS ProArt PX13 (HN7306EAC) |
| ACP | **ACP70** |
| SoundWire | Manager **instance 1** (link 1) |
| Codecs | **Realtek RT721** (dev 3) + dual **TAS2783** (dev 1, 2) |
| Kernel tested | `7.0.0-27-generic` (Ubuntu) |
| Suspend mode | s2idle (`systemctl suspend`) |
| Resume path | `amd_resume_runtime()` → `POWER_OFF` → `manager_reset` |

---

## Reproduction

```text
boot
    ↓
systemctl suspend
    ↓
resume (s2idle)
    ↓
RT721 wait_for_completion_timeout → -110 (FAIL-1)
```

**Fact:** `./scripts/phase6-hunt.sh post-suspend` reports `FAIL-1`, `wait_init_timeout=YES`, `resume_n=1` on vanilla observation builds (Phase 6 patches 0003–0007 only; no behaviour change). Reproduces without userspace recovery scripts.

---

## Investigation tree

Three paths observed across Phase 7 runs (0006b + 0007 + 0006a):

```text
Boot
  STAT1=0x4
        │
        ▼
  IRQ handler (acp63_irq_handler)
        │
        ▼
  irq_thread
        │
        ▼
  ATTACHED
        │
        ▼
  RT721 OK


Resume (vanilla observation)
  STAT1=0x4  (~50 ms after D0)
        │
        ▼
  (no irq_handler_enter)
        │
        ▼
  timeout (-110)


Resume + experiment 0006a
  STAT1=0x4
        │
        ▼
  manual schedule_work
        │
        ▼
  irq_thread
        │
        ▼
  ATTACHED
        │
        ▼
  RT721 OK
```

---

## Observations (boot vs resume)

**Fact:** Linux IRQ number varies by boot (160 / 164 observed). Device name is `ACP_PCI_IRQ`, GSI 13, legacy line (`msi=0`).

| Observation | Boot | Resume |
|-------------|------|--------|
| `manager_reset` | ✓ | ✓ |
| D0 / full software kick `ret=0` | ✓ | ✓ |
| `STAT1 & manager_mask (0x4)` @ +50 ms | 0x4 | **0x4** |
| `irq_handler_enter` (`acp63_irq_handler`) | ✓ | **✗** |
| `sdw1_irq` / ACK path | ✓ | ✗ |
| `amd_sdw_irq_thread` (without intervention) | ✓ | ✗ |
| SoundWire ATTACHED / completion | ✓ | ✗ |
| RT721 `initialization_complete` | ✓ | ✗ (`-110`) |

**Fact (run p7-correlate-d50):** In one resume cycle, `intr_decode post_delay` at t≈51 ms shows `STAT&mask=0x4` while **zero** `irq_handler_enter` lines with `resume≥1` appear in the 5 s RT721 wait window.

**Fact:** CNTL1 is written sequentially on resume: `acp70_host_wake → 0xc00000`, then `amd_manager → 0x400004` (same cycle; not concurrent overwrite).

---

## Facts (demonstrated)

Directly supported by repeated experiments and kernel logs.

- `manager_reset` and full software kick through D0 complete with `ret=0` on FAIL-1 (Phase 6 run 0015).
- Interrupt enable is executed; `INTR_CNTL(1)=0x400004` on FAIL.
- At `post_D0`, `STAT(instance=1) & manager_mask` reads **0**; at **+50 ms** (`post_delay`), it reads **`0x4`** (0006b, 0007 correlate).
- **`acp63_irq_handler()` is not invoked on resume** — no `irq_handler_enter` with `resume≥1` in the FAIL window (0004–0007).
- On **cold boot**, the same `STAT1=0x4` condition is followed by `irq_handler_enter` → `sdw1_irq` → HANDLED (0007).
- **Experimental** `schedule_work(amd_sdw_irq_thread)` when `stat & manager_mask` restores enumeration and RT721 success (0006a, run p7-0006a-d50).
- RT721 `-110` occurs after the above sequence; it is not the first observable failure.
- TAS2783, PipeWire, and userspace rebind are **not required** to reproduce the kernel witness.

---

## Inference

Reasonable conclusions from the facts above. Label as inference when citing upstream.

- A **delivery gap** exists between the manager observing `STAT1 & mask == 0x4` and `acp63_irq_handler()` entry on s2idle resume.
- The downstream SoundWire pipeline (irq thread → enumeration → completion) is **functional** when the worker is scheduled (0006a single-variable experiment).
- Manager resume programming (D0, masks, `INTR_CNTL`) is **unlikely** to be the primary issue — the pending bit is visible at +50 ms with expected mask values.
- MSI misconfiguration is **unlikely** on this platform path (`msi=0`, IO-APIC `ACP_PCI_IRQ`) — **inference**, not traced register-by-register.
- Userspace Dummy Output after resume is **not demonstrated** as the kernel failure cause.

---

## Intervention — experiment 0006a (not a fix)

Phase 7 experiment **0006a** introduced one behaviour change:

```c
if (stat & manager_mask)
    schedule_work(&amd_sdw_irq_thread);
```

> **This modification is not proposed as a fix.** It was introduced solely to determine whether the downstream SoundWire bring-up path was functional once the worker thread was scheduled.

**Facts (run p7-0006a-d50):**

```text
STAT(instance=1) & mask = 0x4 at post_delay
    ↓
manual schedule_work
    ↓
irq_thread → ping_irq → queue_work → handle_status
    ↓
UNATTACHED → ATTACHED (dev 1, 2, 3)
    ↓
completion()
    ↓
RT721 resume_exit ret=0 · ALSA card present
```

**Fact:** `irq_handler_enter` was still absent in that run — the experiment substitutes for whatever the handler would normally trigger.

---

## Phase 7 experimental arc

| Id | Role | Outcome |
|----|------|---------|
| **0005** delay-after-D0 | Timing falsification | **Fact:** STAT evolves 0→`0x4` at +50 ms; enumeration still does not start |
| **0006b** STAT decode | Identify pending bit | **Fact:** instance 1, mask `0x4`, register `ACP_EXTERNAL_INTR_STAT1` |
| **0006a** manual `schedule_work` | Downstream sufficiency test | **Fact:** full enumeration when worker runs (experiment only) |
| **0007** IRQ delivery + correlate | Handler vs STAT same build | **Fact:** STAT pending + handler absent in one resume cycle |

Phase 7 is **closed** for delimitation. Further local work is Phase 8 (ACP platform path), not additional SoundWire manager experiments.

---

## Conclusion

The collected evidence **narrows the investigation** to the platform interrupt delivery path between the ACP interrupt status registers (`ACP_EXTERNAL_INTR_STAT1`) and `acp63_irq_handler()` on s2idle resume.

It does **not** identify the exact missing step — that remains open (see [Remaining questions](#remaining-questions)).

```text
ACP_EXTERNAL_INTR_STAT1  (STAT1 & mask = 0x4 @ ~50 ms)     [observed]
        │
        ▼
Platform interrupt delivery path                          [not fully traced]
        │
        ▼
acp63_irq_handler()                                     [not invoked on resume]
        │
        ▼
schedule_work(amd_sdw_irq_thread)                         [downstream OK if forced — 0006a]
```

**Inference:** SoundWire enumeration logic, slave drivers, and RT721 wait behaviour are unlikely to be the primary defect once the worker runs.

---

## Remaining questions

Questions we can state precisely but cannot yet answer:

1. Why does `STAT1 & manager_mask` become non-zero approximately 50 ms after D0 on resume, but read zero at `post_D0`?
2. Why is `acp63_irq_handler()` not invoked after that point on resume, while it is invoked for the same `STAT1=0x4` condition during cold boot?
3. Is the interrupt not propagated from the ACP block to the IO-APIC/GSI, filtered within the ACP platform driver (`pci-ps.c` / `ps-common.c`), or lost elsewhere — and at which step?
4. Does cold boot vs s2idle resume differ in how legacy IRQ **160/164** (`ACP_PCI_IRQ`) is enabled or unmasked after `acp_hw_resume()`?
5. Is this behaviour specific to ACP70 on this platform, or reproducible on other ACP70 machines / firmware revisions?

---

## Upstream ask

Single question for maintainers:

> Could you advise where the ACP70 resume path restores or re-enables legacy interrupt delivery for the SoundWire manager, and whether there are known differences between the cold-boot and s2idle resume paths?

**Suggested title:**

> ACP70 SoundWire: s2idle resume — manager STAT pending but `acp63_irq_handler` not invoked (ASUS PX13)

**Context to attach:** logs from runs p7-correlate-d50 (delivery) and p7-0006a-d50 (sufficiency experiment), plus this document.

---

## Not demonstrated (do not over-claim)

| Statement | Why |
|-----------|-----|
| The Linux IRQ layer never receives an interrupt | Handler not invoked; IRQ layer not independently traced |
| Hardware never asserts the condition | STAT pending at +50 ms on FAIL |
| Exact register or function at fault | Boot vs resume not yet diffed in ACP code |
| PipeWire causes kernel FAIL-1 | Reproduces without userspace recovery |
| Natural vanilla PASS with observation patches only | Not observed |
| 0006a is a proposed fix | Experiment only |

---

## Ruled-out layers (inference from experiments)

| Layer | Rationale |
|-------|-----------|
| RT721 codec PM | Succeeds when enumeration runs (0006a) |
| TAS2783 / FW | Downstream of missing enumeration |
| SoundWire `bus.c` | ATTACH follows manager notification |
| Incomplete `amd_resume_runtime()` kick | Full sequence `ret=0` (0015) |
| SoundWire manager D0 / mask programming | Pending bit visible with expected CNTL |
| PipeWire / WirePlumber | Not required for kernel witness |

---

## Future work — Phase 8 (local)

Compare **boot vs resume** in ACP platform code (hypothesis targets, not conclusions):

- `acp_hw_resume()` · `acp70_enable_interrupts()`
- `acp70_enable_sdw_host_wake_interrupts()` · `check_and_handle_acp70_sdw_wake_irq()`
- Shared IRQ registration and enable in `pci-ps.c`

---

## Instrumentation policy (Phase 6 + 7 frozen)

> Each patch answers exactly one binary question.

| Question | Answer | Patch / run |
|----------|--------|-------------|
| Full kick `ret=0` on FAIL? | Yes | 0007 / 0015 |
| STAT zero only at post_D0? | Yes; non-zero at +50 ms | 0006b |
| Handler runs on vanilla FAIL? | No | 0004–0007 |
| STAT pending + no handler same build? | Yes | 0007 correlate |
| Manual thread restores enum? | Yes | 0006a (experiment) |

---

## Attachments (when submitting)

1. `validation/phase6-runs/hunt-p7-correlate-d50/kmsg-phase6-window.log`
2. `validation/phase6-runs/hunt-p7-0006a-d50/` (intervention witness)
3. FAIL reference: run 0015 window log
4. `./scripts/phase6-hunt.sh post-suspend` output
5. `./scripts/phase6-state-machine.sh` for correlate boot
6. `journalctl -k -b 0 | grep -E 'PHASE7 ctx=(acp|amd) fn='` excerpt
7. This document

---

## Appendix — environment detail

| Field | Value |
|-------|-------|
| Observation instrumentation | Phase 6 patches 0003–0007 (no behaviour changes) |
| Phase 7 | 0006b decode, 0006a experiment, 0007 pci-ps + correlate |
| FAIL witness (vanilla) | Run **0015**, `resume=1` |
| Delivery witness | Run **p7-correlate-d50**, `resume=1` |
| Intervention witness | Run **p7-0006a-d50**, `resume=1` |

Full narrative: [../JOURNEY.md#investigation-summary](../JOURNEY.md#investigation-summary).

---

## Appendix — contrast table (vanilla FAIL vs 0006a)

| Probe | Vanilla FAIL | 0006a experiment |
|-------|--------------|------------------|
| `manager_reset` | ✓ | ✓ |
| `post_delay` STAT&mask | **0x4** | **0x4** |
| `irq_handler_enter` | ✗ | ✗ |
| `manual_irq_schedule` | — | **FIRED** |
| `irq_thread_enter` | ✗ | ✓ |
| `completion()` | ✗ | ✓ |
| RT721 | `-110` | **ret=0** |

A natural PASS row (handler runs without 0006a) would still be valuable for a golden diff.
