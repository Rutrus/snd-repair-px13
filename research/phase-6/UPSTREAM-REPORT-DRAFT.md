# Upstream report draft — ACP70 SoundWire s2idle resume (PX13)

English (canonical). **Submittable** — FAIL path delimited through Phase 7 experiment 0006a.

Related: [KNOWN-FACTS.md](KNOWN-FACTS.md) · [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md) · [../JOURNEY.md](../JOURNEY.md) · [../phase-7/experiments/0006a-run-p7-d50.md](../phase-7/experiments/0006a-run-p7-d50.md)

**Reading guide:** maintainers can start at [Objective findings](#objective-findings-demonstrated) and [Remaining question](#remaining-question).

---

## Investigation phase

| Phase | Status |
|-------|--------|
| **Delimitation** (where does it break?) | **Complete** — Phase 6 run 0015 + Phase 7 0006a |
| **Explanation** (why does IRQ not reach handler?) | **Open** — pci-ps / MSI / resume restore |

This report separates **demonstrated facts**, **supported inferences**, and **open questions**.

---

## Environment

| Field | Value |
|-------|-------|
| Machine | ASUS ProArt PX13 (HN7306EAC) |
| ACP | ACP70 SoundWire |
| Kernel | `7.0.0-27-generic` (Ubuntu) |
| Suspend | s2idle (`systemctl suspend`) |
| Path | `amd_resume_runtime()` `POWER_OFF` / `manager_reset` |
| Observation instrumentation | Phase 6 patches 0003–0007 (no behaviour changes) |
| Phase 7 instrumentation | 0006b decode + 0006a single intervention (see below) |
| FAIL witness (vanilla) | Run **0015**, `resume=1` (clean boot) |
| Intervention witness | Run **p7-0006a-d50**, `resume=1`, 0006a Outcome A |

---

## Initial symptom

After s2idle resume, internal audio failed intermittently. Visible symptoms: RT721 `-ETIMEDOUT` (`-110`), TAS2783 `:8 done=0`, userspace often Dummy Output. Failure location was initially unknown.

---

## Progressive narrowing (summary)

| Stage | Result |
|-------|--------|
| Phase 1–3 | FAIL-1 vs FAIL-2 classified; FAIL-1 reproducible on clean boot |
| Phase 4–5 | TAS2783, RT721, PipeWire scripts, bus.c ruled out as **first** failure |
| Phase 6 | Gap between `irq_enabled` and re-enumeration; full software kick `ret=0` |
| Phase 7 | STAT pending at +50 ms; manual `schedule_work` restores full path |

Full narrative: [../JOURNEY.md#investigation-summary](../JOURNEY.md#investigation-summary).

---

## Observed sequence (FAIL-1, vanilla, repeated runs)

Log-supported chain (run 0015; refined by 0006b at +50 ms):

```text
system_resume
    ↓
amd_resume_runtime()
    ↓
manager_reset
    ↓
clear_slave_status → init_sdw_manager (ret=0) → enable_sdw_manager (ret=0)
    ↓
enable interrupts (irq_enabled)
    ↓
program registers (INTR_CNTL, SDW_EN, FRAME, device_state D0 — ret=0)
    ↓
post_D0: STAT(instance=1) & mask = 0          [0006b]
    ↓
+50 ms: STAT(instance=1) & mask = 0x4          [0006b]
    ↓
(no acp63_irq_handler / no irq_thread in vanilla FAIL window)
    ↓
SoundWire slaves remain UNATTACHED
    ↓
initialization_complete never signalled
    ↓
RT721 wait_for_completion_timeout → -110
```

---

## Phase 7 experiments

### 0005 — delay after D0 (negative as fix)

Adding `phase7_delay_ms=50` after D0 showed STAT evolves from 0 to `0x4` on instance 1. Enumeration still did not start; no handler. **Conclusion:** timing alone does not fix FAIL-1; delay exposes pending status.

### 0006b — STAT decode (observation)

On PX13 link 1 → manager instance **1** → mask **`0x4`** on **`ACP_EXTERNAL_INTR_STAT1`** (`ACP_SDW1_STAT`). Removed earlier STAT0/`0x200000` misread.

### 0006a — validate manager mask (decisive)

**Only behaviour change:**

```c
if (stat & manager_mask)
    schedule_work(&amd_sdw_irq_thread);
```

**Observed (run p7-0006a-d50):**

```text
STAT(instance=1) & mask = 0x4 at post_delay
    ↓
manual schedule_work (0006a)
    ↓
irq_thread_enter (+51 ms)
    ↓
ping_irq → ping_status → queue_work → handle_status
    ↓
UNATTACHED → ATTACHED (dev 1, 2, 3)
    ↓
completion()
    ↓
RT721 resume_exit ret=0
    ↓
ALSA card / PCM devices present
```

Still **no** `irq_handler_enter` (PCI ISR path) in this run. The intervention injects the trigger the handler would normally provide.

---

## Objective findings (demonstrated)

Statements directly supported by repeated experiments and kernel logs.

- `manager_reset` executes on system resume (FAIL-1).
- Manager init/enable and D0 transition complete with `ret=0` (0015).
- Interrupt enable executes (`irq_enabled` logged).
- Register programming reads as expected on FAIL (`INTR_CNTL=0x400004`, `SDW_EN=1`, `FRAME=0xc`).
- At `post_D0`, `STAT(instance=1) & manager_mask` reads **0** (0006b).
- At **+50 ms** (`post_delay`), `STAT(instance=1) & manager_mask` reads **`0x4`** (0006b, p7-0006b-d50).
- **`acp63_irq_handler` does not run** in vanilla FAIL-1 (`irq_handler_enter` absent).
- **Manual `schedule_work(amd_sdw_irq_thread)` when `stat & manager_mask`** restores full SoundWire enumeration and RT721 success (0006a).
- RT721 `-110` occurs **after** the above; it is not the first failure.
- TAS2783, PipeWire, and userspace rebind are **not required** to reproduce the kernel witness path.

---

## Supported inferences (label as inference upstream)

- The SoundWire pipeline after `amd_sdw_irq_thread` is **functional** when the worker runs (0006a single-variable test).
- The defect is at **IRQ delivery** (STAT pending → handler missing), not manager resume programming or slave drivers.
- Userspace Dummy Output may persist briefly after kernel recovery; **not demonstrated** as root cause (FACT 9).

---

## Not demonstrated (do not over-claim)

| Statement | Why it is not proven |
|-----------|----------------------|
| Hardware never asserts the interrupt | +50 ms decode shows pending bit on FAIL |
| MSI routing is broken | Plausible; not yet traced register-by-register |
| PipeWire causes kernel FAIL-1 | Kernel witness reproduces without userspace recovery |
| WirePlumber leaves profile `off` | Not captured post-resume without reboot |
| Exact silicon / firmware bug | Open |
| Natural vanilla PASS with 0003–0007 only | Not observed (`PASS-0006a` requires intervention) |

---

## Remaining question

One kernel boundary:

```text
ACP manager — STAT(instance=1) & mask pending
        ↓
        ?   ← open
        ↓
acp63_irq_handler()
        ↓
schedule_work(amd_sdw_irq_thread)
```

**Why does the normal interrupt path fail after s2idle resume when the manager STAT bit is pending?**

Candidate areas (hypotheses, not conclusions):

- MSI/MSI-X restore after s2idle
- interrupt mask / routing in `sound/soc/amd/ps/pci-ps.c`
- difference between cold boot and `POWER_OFF` resume
- ACP70 platform-specific wake vs SDW1 STAT path

---

## Contrast table (vanilla FAIL vs 0006a intervention)

| Probe | Vanilla FAIL (0015 / 0006b) | 0006a (p7-0006a-d50) |
|-------|----------------------------|----------------------|
| `manager_reset` | ✓ | ✓ |
| Full kick `ret=0` | ✓ | ✓ |
| `post_D0` STAT&mask | 0 | 0 |
| `post_delay` STAT&mask | **0x4** | **0x4** |
| `irq_handler_enter` | ✗ | ✗ |
| `manual_irq_schedule` | — | **FIRED** |
| `irq_thread_enter` | ✗ | ✓ (+51 ms) |
| `completion()` | ✗ | ✓ |
| RT721 | timeout (`-110`) | **ret=0** |

A natural PASS row (handler runs without 0006a) would still be valuable for golden diff; **0006a already proves sufficiency of the thread path**.

---

## Ruled-out root-cause layers

| Layer | Rationale |
|-------|-----------|
| RT721 codec PM | Waits on `initialization_complete()`; succeeds when enumeration runs (0006a) |
| TAS2783 / FW | Downstream of missing enumeration |
| SoundWire `bus.c` | ATTACH follows manager notification |
| Incomplete `amd_resume_runtime()` | Full sequence observed (0015) |
| PipeWire / WirePlumber | Not required for kernel witness; secondary UX layer |

---

## Future work (recommended)

1. Trace `ACP_EXTERNAL_INTR_STAT1` in `pci-ps.c` at handler entry vs manager decode snapshots (same resume window).
2. Compare MSI enable / mask state: cold boot vs first s2idle resume.
3. Optional: second ACP70 machine for generality.

**Not recommended** unless new evidence: RT721, TAS2783, slave drivers, PipeWire policy.

Proposed probes: [proposed/NEXT-ACP-HW-IRQ-TRACE.md](proposed/NEXT-ACP-HW-IRQ-TRACE.md).

---

## Instrumentation policy (frozen for delimitation)

> Each patch answers exactly one binary question.

Phase 6 + Phase 7 questions now answered — do not add horizontal trace by default:

| Question | Answer | Patch / run |
|----------|--------|-------------|
| Full kick `ret=0` on FAIL? | Yes | 0007 / 0015 |
| STAT zero only at post_D0? | Yes; **non-zero at +50 ms** | 0006b |
| Handler runs on vanilla FAIL? | No | 0004–0006b |
| Manual thread restores enum? | **Yes** | **0006a / p7-d50** |

---

## Attachments (when submitting)

1. `validation/phase6-runs/hunt-p7-0006a-d50/kmsg-phase6-window.log` (or equivalent)
2. FAIL reference: run 0015 window log
3. `./scripts/phase6-hunt.sh post-suspend` output (PASS-0006a classifier)
4. `./scripts/phase6-state-machine.sh` for same boot
5. This document + [0006a-run-p7-d50.md](../phase-7/experiments/0006a-run-p7-d50.md)

---

## Suggested upstream title

> ACP70 SoundWire: s2idle resume — manager STAT pending but `acp63_irq_handler` not invoked (ASUS PX13)

## Suggested ask

> We have localized a FAIL-1 s2idle resume on ACP70 to the boundary between pending `ACP_SDW1_STAT` (instance 1, mask 0x4) and `acp63_irq_handler` entry. Manager re-init completes with `ret=0`; manually scheduling `amd_sdw_irq_thread` when `stat & manager_mask` fully restores enumeration (experiment 0006a, logs attached).
>
> Could you advise whether interrupt delivery after `POWER_OFF` resume is known to require additional steps in `pci-ps.c`, or whether this matches a known MSI/routing issue on ACP70? We can provide further pci-ps tracing on request.

---

## Scenario status

Per [UPSTREAM-STRATEGY.md](UPSTREAM-STRATEGY.md):

- **Scenario 1** (natural PASS + FAIL golden diff): still desirable; not required to submit delimitation.
- **Scenario 2** (FAIL localized + intervention proves sufficiency): **met** via 0015 + 0006a.
- **Scenario 3** (deterministic FAIL): supported by hunt log; strengthens reproduction.

**PASS hunt** with vanilla 0003–0007 remains optional; primary upstream value is the 0006a causal test.
