# Phase 6 — Known facts (ACP70 / PX13)

English (canonical). **One page.** Facts supported by repeated runs — not hypotheses.

**Rule:** If a future run contradicts a fact, update this file and cite the run. Do not re-debate ruled-out items without new evidence.

**Patch rule:** Each new patch must answer **exactly one binary question** — see [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md#instrumentation-policy-frozen).

Status / runs: [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md)

---

## Phase boundary (objective shift)

| Iteration | First unknown transition |
|-----------|--------------------------|
| Early Phase 6 | `manager_reset` → **?** → `wait_init_timeout` |
| Run **0013** (0005) | `irq_enabled` → **`ACP_EXTERNAL_INTR_STAT = 0`** → (no IRQ) |
| Run **0014** (0006) | Block configured (`CNTL`, `EN`, `FRAME`) but **`STAT = 0`** → (no IRQ) |
| Run **0015** (0007) | Full software kick sequence **`ret=0`**; **`STAT = 0`** post-D0 → (no IRQ) |
| **Now** | **Delimitation complete** — experimental **PASS vs FAIL** contrast (not more FAIL trace) |

**Investigation goal:** obtain the [golden diff](UPSTREAM-REPORT-DRAFT.md#golden-diff-primary-experimental-goal). FAIL column filled (0015); PASS column pending.

Report draft (submit without PASS if wording is conservative): [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md).

---

## Demonstrated vs not demonstrated

### Demonstrated (maintainer-safe)

1. Full `amd_resume_runtime()` `POWER_OFF` sequence runs on FAIL-1 (0015): `manager_reset` through `device_state_D0`, all instrumented steps `ret=0`.
2. `INTR_CNTL`, `SDW_EN`, `FRAME` read as programmed on FAIL (0014–0015).
3. `ACP_EXTERNAL_INTR_STAT` is **0** on instrumented reads after enable, bringup, and D0.
4. **No** `irq_handler_enter` / `irq_thread_enter` during the RT721 wait window (~5 s).
5. **No** downstream SoundWire enumeration activity before RT721 `-110`.
6. RT721, TAS2783, `bus.c` are **not** the first failure.

### Not demonstrated (do not over-claim)

| Claim | Why not |
|-------|---------|
| Hardware never asserts interrupt | Only single-point reads + no handler in window |
| Wrong register values on FAIL | Reads match expected programmed state |
| Which HW mechanism inside open box | Needs PASS diff or AMD HW input |

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

## FACT 11 — ACP block reads configured on FAIL (run 0014; 0006)

Run **0014** (`run-14-0006`, resume=1, FAIL-1):

| Probe | Value |
|-------|-------|
| `intr_cntl_post_enable` | `0x400004` |
| `intr_stat_post_enable` | `0x0` |
| `sdw_en_post_resume` | `0x1` |
| `clk_frame` | `0xc` |
| `intr_stat_post_bringup` | `0x0` |

Still: no `irq_handler_enter`, no `irq_thread_enter`, `wait_init_timeout`, RT721 `-110`.

**Ruled out on 0014 (maintainer-safe):** *"Resume path failed to program INTR_CNTL / enable SDW / set frame."* Registers read as expected; **no pending interrupt visible** at both post-enable and post-bringup reads.

**What remains:** the step that should make hardware assert the first `ACP_EXTERNAL_INTR_STAT` bit (see [proposed/NEXT-RESUME-KICK.md](proposed/NEXT-RESUME-KICK.md)). AMD has no explicit `start_bus()` — first event is hardware-autonomous after manager enable + frameshape (+ ACP70 `D0`).

---

## FACT 12 — Full resume kick sequence runs on FAIL; still no HW event (run 0015; 0007)

Run **0015** (clean boot, `resume=1`, FAIL-1, 0007):

| Kick probe | Result |
|------------|--------|
| `clk_resume_skip` | logged (no clock-resume reg) |
| `clear_slave_status` | yes |
| `init_sdw_manager` | `ret=0` |
| `enable_sdw_manager` | `ret=0` |
| `frameshape_done` | yes |
| `device_state_D0` | `ret=0` `val=0x0` (D0 encodes as 0 — expected) |
| `intr_stat_post_D0` | `0x0` |

Same block reads as FACT 11 (`CNTL=0x400004`, `EN=1`, `FRAME=0xc`). Still: no `irq_handler_enter`, no `irq_thread_enter`, `wait_init_timeout`, RT721 `-110`.

**Ruled out on 0015 (maintainer-safe):** *"A software kick step on the AMD resume path did not run or failed before completion."* Every instrumented step through `device_state_D0` completed with `ret=0`; **no `ACP_EXTERNAL_INTR_STAT` bit and no IRQ** in the wait window.

**Strongest FAIL witness to date** for upstream: software sequence complete; first hardware-autonomous event never observed.

---

## FACT 13 — No kernel witness PASS with 0003–0007 (as of 0015)

With Phase 6 AMD instrumentation (0003–0007), **no run to date** shows on clean-boot first suspend (`resume=1`):

- `irq_handler_enter` + `ping_irq` + `completion()`, and
- absence of `wait_init_timeout` / RT721 `-110`,

without userspace recovery (`px13-audio-rebind`, PCI reset, etc.).

Instrumented FAIL-1 on `resume=1` **is** repeated (0010, 0012, 0013, 0014, 0015).

**Userspace audio OK ≠ kernel PASS** (FACT 9). Early run 0002 reported kernel-side RT721 success **before** full AMD trace — not a golden-diff PASS.

**If this holds after bounded PASS hunt (≥20 attempts):** treat as **deterministic kernel FAIL** on this platform; upstream question becomes *why first post-reset HW event is never observed*, not *why PASS/FAIL diverge*. See [UPSTREAM-STRATEGY.md](UPSTREAM-STRATEGY.md).

---

## FACT 8 — FAIL-2 is a distinct witness class

`resume_early_exit reason=first_hw_init` — RT721 **does not wait**. Often a cascade after a prior FAIL in the same boot (`resume=2+`).

Runs: 0007, 0011. Do not confuse with PASS.

---

## FACT 9 — Userspace `OK/WARN` ≠ audio PASS

Chronology composite can show OK while the sink is Dummy / no FW. The kernel witness path is authoritative.

---

## FACT 10 — Investigation scope (updated run 0015)

**FAIL path instrumentation is complete.** Do not add RT721, TAS2783, `bus.c`, or horizontal AMD existence probes (0008+) without evidence that breaks FACT 1–12 or a PASS/FAIL diff that opens a new question.

**Active work:** PASS capture with 0003–0007 — see [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md).

The open question is at the **hardware boundary** after software kick sequence completes, not in downstream SoundWire or codecs.

---

## Frozen (do not touch for root-cause investigation)

- RT721 / TAS2783 behavior patches and **trace** — witness role complete  
- Machine driver, `soc_sdw_utils`  
- Phase 5 FW reload (0003)  
- PipeWire / `px13-audio-rebind`  
- `bus.c` trace — question answered  
- **AMD 0008+** horizontal instrumentation — default **no**; see [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md)

**Keep:** 0003–0007 installed for PASS/FAIL contrast only.

---

## Upstream one-liner (FAIL)

> On s2idle resume (FAIL-1, run 0015), the instrumented `POWER_OFF` resume sequence completes with all observed steps returning 0; control registers read as programmed; **`ACP_EXTERNAL_INTR_STAT` is 0** on reads after enable, bringup, and D0; **no IRQ handler runs** during the ~5 s before RT721 times out; re-enumeration never starts in the log window.

**Do not write:** *hardware never asserts interrupt.* **Do write:** the observation above.

**Next:** [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md) · If PASS never appears: [UPSTREAM-STRATEGY.md](UPSTREAM-STRATEGY.md)

**Gold contrast (same instrumentation — highest upstream value):**

| | FAIL (0015) | PASS (target) |
|--|-------------|---------------|
| `resume=` | 1 (clean boot) | 1 |
| All kick probes | `ret=0` | same |
| `INTR_CNTL` / `SDW_EN` / `FRAME` | programmed | same |
| `intr_stat_post_D0` | **0** | **≠0** |
| IRQ handler | no | yes |
| `completion()` | no | yes |
| RT721 | `-110` | OK |

```text
FAIL:  kicks complete → STAT=0 post-D0 → (no handler) → timeout
PASS:  kicks complete → STAT≠0 post-D0 → handler → … → completion
```
