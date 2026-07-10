# Phase 6 — Known facts (ACP70 / PX13)

English (canonical). **One page.** Facts supported by repeated runs — not hypotheses.

**Rule:** If a future run contradicts a fact, update this file and cite the run. Do not re-debate ruled-out items without new evidence.

Status / runs: [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md)

---

## Precise problem statement

> The first observable failure occurs **after** `amd_resume_runtime()` runs `manager_reset` and re-enables interrupts. From that point, **no log evidence** of SoundWire re-enumeration activity appears until RT721 exhausts `wait_for_completion_timeout()` (~5 s, `-110`).

This chain does **not** depend on TAS2783, PipeWire, or userspace recovery scripts.

---

## FACT 1 — `manager_reset` always runs on system resume (FAIL-1 runs)

Observed on every instrumented FAIL-1 window with AMD trace (`resume=N`, `pm=system_resume`).

Runs: 0004–0006, 0008–0010, 0012.

---

## FACT 2 — `irq_enabled` always runs after `manager_reset` (post-0004)

`amd_enable_sdw_interrupts()` completes; log `fn=irq_enabled` appears immediately after reset.

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

Runs: 0010, 0012 (and pre-0004 FAILs consistent with same gap).

---

## FACT 4 — RT721 `-110` is a consequence, not the root cause

FAIL-1: `wait_init_start` → kernel `t=+~5000ms` → `wait_init_timeout` → `ret=-110`.

RT721 waits for `initialization_complete()` that never arrives because FACT 3.

---

## FACT 5 — TAS2783 / FW is never the first failure

No FW reload path matters if bus never completes enumeration. TAS2783 `playback without fw` appears **after** link is already broken.

**Frozen:** TAS2783 FW patches, machine driver, `soc_sdw_utils` for root-cause work.

---

## FACT 6 — `IO_PAGE_FAULT` is not necessary for FAIL

Run **0010** and **0012**: FAIL-1 with **no** `IO_PAGE_FAULT` in resume window.

Some other FAILs show correlation — track as **observation**, not cause.

---

## FACT 7 — First known gap (reproducible)

```text
irq_enabled
      │
      ├──────────────  ← first reproducible gap (0010, 0012)
      │  (no ACP IRQ activity in log)
      ├──────────────
      │
      ▼
(no ATTACHED / no completion)
      ▼
RT721 timeout (-110)
```

**Not yet proven:** whether hardware never asserts the interrupt (S1) vs interrupt exists but never reaches the handler (S2). That requires patch **0005** (`intr_stat_post_enable` + `irq_handler_enter`).

**Conservative wording:** we have *no log evidence of IRQ activity* — not a proof that hardware never asserted until 0005 runs.

---

## FACT 8 — FAIL-2 is a distinct witness class

`resume_early_exit reason=first_hw_init` — RT721 **does not wait**. Often cascade after prior FAIL in same boot (`resume=2+`).

Runs: 0007, 0011. Do not confuse with PASS.

---

## FACT 9 — Userspace `OK/WARN` ≠ audio PASS

Chronology composite can show OK while sink is Dummy / no FW. Kernel witness path is authoritative.

---

## Frozen (do not touch for root-cause investigation)

- RT721 / TAS2783 behavior patches  
- Machine driver, `soc_sdw_utils`  
- Phase 5 FW reload (0003)  
- PipeWire / `px13-audio-rebind`  
- Additional `bus.c` trace (question answered)

**Active layer:** ACP PCI IRQ path only until S1/S2 resolved.

---

## Upstream one-liner (FAIL)

> After s2idle resume on AMD ACP70, `manager_reset` and interrupt re-enable succeed. Re-enumeration IRQ/work activity does not appear in the log window; slaves never return to ATTACHED; RT721 `-110` is downstream.

**Gold contrast (when captured):**

```text
FAIL:  reset → irq_enabled → (silence) → timeout
PASS:  reset → irq_enabled → handler → … → ATTACHED → completion
```
