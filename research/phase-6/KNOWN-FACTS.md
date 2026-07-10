# Phase 6 — Known facts (ACP70 / PX13)

English (canonical). **One page.** Facts supported by repeated runs — not hypotheses.

**Rule:** If a future run contradicts a fact, update this file and cite the run. Do not re-debate ruled-out items without new evidence.

Status / runs: [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md)

---

## Phase boundary (objective shift)

| Iteration | First unknown transition |
|-----------|--------------------------|
| Early Phase 6 | `manager_reset` → **?** → `wait_init_timeout` |
| Run **0013** (0005) | `irq_enabled` → **`ACP_EXTERNAL_INTR_STAT = 0`** → (no IRQ) |

We no longer infer the break from missing `completion()` alone. Run 0013 found the **first observable state** that differs from expected PASS behaviour.

**Investigation goal now:** explain why the ACP block does not present the expected post-reset state — not *where* the sequence breaks.

---

## Precise problem statement

> The first observable failure occurs **after** `amd_resume_runtime()` runs `manager_reset` and re-enables interrupts. From that point, **no log evidence** of SoundWire re-enumeration activity appears until RT721 exhausts `wait_for_completion_timeout()` (~5 s, `-110`).

This chain does **not** depend on TAS2783, PipeWire, or userspace recovery scripts.

---

## FACT 1 — `manager_reset` on system resume (FAIL-1)

Observed in **every instrumented FAIL-1 run to date** with AMD trace (`resume=N`, `pm=system_resume`).

Runs: 0004–0006, 0008–0010, 0012, **0013**.

---

## FACT 2 — `irq_enabled` after `manager_reset` (post-0004)

Observed in **every instrumented FAIL-1 run to date** with patch 0004+: `amd_enable_sdw_interrupts()` completes; log `fn=irq_enabled` appears immediately after reset.

Runs: **0010**, **0012**, **0013** (reproducible clean-boot FAIL-1).

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

Runs: 0010, 0012, **0013** (and pre-0004 FAILs consistent with the same gap).

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

## FACT 7 — First known gap (run 0013; S1, S2 ruled out on that run)

```text
manager_reset
      ↓
irq_enabled
      ↓
ACP_EXTERNAL_INTR_STAT = 0x0     ← 0013, read immediately post-enable
      ↓
(no observed IRQ handler / thread)
      ↓
(no ATTACHED / no completion)
      ↓
RT721 timeout (-110)
```

**Run 0013 (`run-13-s1s2`, resume=1) — irrefutable wording:**

> On the instrumented read immediately after `irq_enabled`, `ACP_EXTERNAL_INTR_STAT` is **0x0**, and **no IRQ handler activity** was observed during the RT721 wait window (`irq_handler_enter` / `irq_thread_enter` absent; `wait_init_timeout` at kernel t=+5131ms).

**Do not equate** `STAT=0` with *"hardware never generates the event."* That is a hypothesis compatible with the observation, not the observation itself.

**Ruled out on 0013 (maintainer-safe):** **S2** — not *stat≠0 with no handler*; observed *stat=0* and no handler.

**What `STAT=0` does not identify by itself:**

1. Event **never generated** (most likely given full wait window with no handler).
2. Event generated **later** — single post-enable read may miss it (would need STAT poll or PASS trace).
3. Event requires a **prior kick** (clock, power, first PING, FW) that never occurs on this path.

`STAT=0` locates the break; it does not name which mechanism failed.

Earlier runs (0010, 0012) established silence after `irq_enabled`; 0005 / 0013 names **stat=0 + S1**.

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

The first missing transition is **identified** (FACT 7): `irq_enabled` → `STAT=0` → no IRQ to software.

Investigation is now **why `ACP_EXTERNAL_INTR_STAT` stays 0** after `manager_reset` — ACP70 HW / sequencing only. **No further SoundWire or codec instrumentation** without new evidence.

Do not propose RT721 or TAS2783 trace changes without evidence that breaks FACT 3–5.

---

## Frozen (do not touch for root-cause investigation)

- RT721 / TAS2783 behavior patches  
- Machine driver, `soc_sdw_utils`  
- Phase 5 FW reload (0003)  
- PipeWire / `px13-audio-rebind`  
- Additional `bus.c` trace (question answered)

**Active layer:** ACP70 — why `ACP_EXTERNAL_INTR_STAT` is 0 after reset (see [proposed/NEXT-ACP-STAT-ZERO.md](proposed/NEXT-ACP-STAT-ZERO.md)). S2 ruled out on run 0013.

---

## Upstream one-liner (FAIL)

> After s2idle resume on AMD ACP70, `manager_reset` and interrupt re-enable succeed, but `ACP_EXTERNAL_INTR_STAT` reads **0** immediately after enable and no IRQ reaches the handler; re-enumeration never starts; RT721 `-110` is downstream.

**Gold contrast (same instrumentation — highest upstream value):**

| | FAIL (0013) | PASS (target) |
|--|-------------|---------------|
| `irq_enabled` | yes | yes |
| `ACP_EXTERNAL_INTR_STAT` | **0** | **≠0** |
| IRQ handler | no | yes |
| `completion()` | no | yes |
| RT721 | `-110` | OK |

```text
FAIL:  irq_enabled → STAT=0 → (no handler) → timeout
PASS:  irq_enabled → STAT≠0 → handler → … → completion
```
