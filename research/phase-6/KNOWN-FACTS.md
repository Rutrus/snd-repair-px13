# Phase 6 — Known facts (ACP70 / PX13)

English (canonical). **One page.** Facts supported by repeated runs — not hypotheses.

**Rule:** If a future run contradicts a fact, update this file and cite the run. Do not re-debate ruled-out items without new evidence.

Status / runs: [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md)

---

## Precise problem statement

> The first observable failure occurs **after** `amd_resume_runtime()` runs `manager_reset` and re-enables interrupts. From that point, **no log evidence** of SoundWire re-enumeration activity appears until RT721 exhausts `wait_for_completion_timeout()` (~5 s, `-110`).

This chain does **not** depend on TAS2783, PipeWire, or userspace recovery scripts.

---

## FACT 1 — `manager_reset` on system resume (FAIL-1)

Observed in **every instrumented FAIL-1 run to date** with AMD trace (`resume=N`, `pm=system_resume`).

Runs: 0004–0006, 0008–0010, 0012.

---

## FACT 2 — `irq_enabled` after `manager_reset` (post-0004)

Observed in **every instrumented FAIL-1 run to date** with patch 0004+: `amd_enable_sdw_interrupts()` completes; log `fn=irq_enabled` appears immediately after reset.

Runs: **0010**, **0012** (reproducible clean-boot FAIL-1).

**Ruled out:** *"AMD never re-enables interrupts after resume."*

---

## FACT 3 — FAIL-1: no re-enumeration activity in log window

After `irq_enabled`, for matching `resume=N`:

| Step | Log evidence (FAIL-1) |
|------|------------------------|
| `sdw0_irq` | **No** |
| `ping_irq` | **No** |
| `queue_work` | **No** |
| `handle_status` | **No** |
| bus `UNATTACHED → ATTACHED` | **No** |
| `completion()` | **No** |

Runs: 0010, 0012 (and pre-0004 FAILs consistent with the same gap).

**No evidence of any transition from the ACP manager into the SoundWire enumeration path was observed after `irq_enabled`.**

---

## FACT 4 — RT721 `-110` is a consequence, not the root cause

FAIL-1: `wait_init_start` → kernel `t=+~5000ms` → `wait_init_timeout` → `ret=-110`.

RT721 **blocks waiting** for `initialization_complete()` that never arrives because FACT 3.

---

## FACT 5 — TAS2783 / FW is not the first failure

No FW reload path matters if bus never completes enumeration. TAS2783 `playback without fw` appears **after** the link is already broken.

**No evidence currently places TAS2783 before the missing enumeration event.**

**Frozen:** TAS2783 FW patches, machine driver, `soc_sdw_utils` for root-cause work.

---

## FACT 6 — `IO_PAGE_FAULT` is not necessary for FAIL

Runs **0010** and **0012**: FAIL-1 with **no** `IO_PAGE_FAULT` in the resume window.

Some other FAILs show correlation — track as **observation**, not cause.

---

## FACT 7 — First known gap; S1 on run 0013 (0005)

```text
irq_enabled
      │
      ├──────────────  ← gap (0010, 0012: no observed IRQ activity)
      │  intr_stat_post_enable = 0x0   (0013, immediately post-enable)
      │  irq_handler_enter = none    (0013, full wait window)
      ├──────────────  → S1 pattern (not S2)
      │
      ▼
(no ATTACHED / no completion)
      ▼
RT721 timeout (-110)
```

**Run 0013 (`run-13-s1s2`, resume=1):** after `irq_enabled`, `intr_stat_post_enable stat=0x0`; no `irq_handler_enter` or `irq_thread_enter` before `wait_init_timeout` at kernel t=+5131ms. **`sm` verdict: S1** — no pending interrupt visible at enable time and no handler activity during wait.

**Conservative reading:** compatible with the ACP block **not asserting** a post-reset interrupt (hardware / firmware / sequencing). **Rules out S2** on this run (stat≠0 but no handler). Does not prove the bit never toggles later without a later STAT poll; does prove no delivered IRQ reached software in the wait window.

Earlier runs (0010, 0012) established the gap before 0005; 0013 names it **S1**.

---

## FACT 8 — FAIL-2 is a distinct witness class

`resume_early_exit reason=first_hw_init` — RT721 **does not wait**. Often a cascade after a prior FAIL in the same boot (`resume=2+`).

Runs: 0007, 0011. Do not confuse with PASS.

---

## FACT 9 — Userspace `OK/WARN` ≠ audio PASS

Chronology composite can show OK while the sink is Dummy / no FW. The kernel witness path is authoritative.

---

## FACT 10 — Investigation scope

The current root-cause investigation is limited to the **ACP interrupt and re-enumeration path**.

Further instrumentation below the codec layer is **intentionally frozen** until the first missing transition between `irq_enabled` and SoundWire re-enumeration is identified.

Do not propose RT721 or TAS2783 trace changes without new evidence that breaks FACT 3–5.

---

## Frozen (do not touch for root-cause investigation)

- RT721 / TAS2783 behavior patches  
- Machine driver, `soc_sdw_utils`  
- Phase 5 FW reload (0003)  
- PipeWire / `px13-audio-rebind`  
- Additional `bus.c` trace (question answered)

**Active layer:** ACP block post-`irq_enabled` — why `ACP_EXTERNAL_INTR_STAT` is 0x0 after reset (S1). IRQ routing (S2) ruled out on run 0013.

---

## Upstream one-liner (FAIL)

> After s2idle resume on AMD ACP70, `manager_reset` and interrupt re-enable succeed. No observed transition from the ACP manager into SoundWire re-enumeration occurs in the log window; slaves never return to ATTACHED; RT721 `-110` is downstream.

**Gold contrast (when captured):**

```text
FAIL:  reset → irq_enabled → (no observed IRQ activity) → timeout

PASS:  reset → irq_enabled → ACP IRQ → ping → queue_work → ATTACHED → completion
```

Until PASS is captured, 0005 S1/S2 bisect remains the next step — not a return to codec-layer instrumentation.
