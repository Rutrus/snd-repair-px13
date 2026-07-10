# Upstream report draft — ACP70 SoundWire s2idle resume (PX13)

English (canonical). **Submit-ready skeleton** — FAIL evidence complete; PASS column to fill when captured.

Related: [KNOWN-FACTS.md](KNOWN-FACTS.md) · [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md)

---

## Investigation phase

| Phase | Status |
|-------|--------|
| **Delimitation** (where does it break?) | **Complete** — run 0015 |
| **Explanation** (why does HW not present first event?) | **Open** — needs PASS contrast or AMD HW input |

Delimitation and explanation are different deliverables. This report separates **observed facts** from **inference**.

---

## Environment

| Field | Value |
|-------|-------|
| Machine | ASUS ProArt PX13 (HN7306EAC) |
| ACP | ACP70 SoundWire |
| Kernel | `7.0.0-27-generic` (Ubuntu) |
| Suspend | s2idle (`systemctl suspend`) |
| Path | `amd_resume_runtime()` `POWER_OFF` / `manager_reset` |
| Instrumentation | Phase 6 observation patches 0003–0007 (no behaviour changes) |
| FAIL witness | Run **0015**, `resume=1` (clean boot) |

---

## Observed sequence (FAIL-1, repeated runs)

Not a hypothesis about RT721 — the log-supported chain:

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
program registers (INTR_CNTL, SDW_EN, FRAME, device_state D0 — all ret=0 on 0015)
    ↓
(no observable interrupt processing in ~5 s window)
    ↓
SoundWire slaves remain UNATTACHED
    ↓
initialization_complete never signalled
    ↓
RT721 wait_for_completion_timeout → -110
```

---

## Observed (maintainer-safe)

- `manager_reset` executes on system resume (FAIL-1).
- Manager init/enable steps complete with `ret=0` (0015).
- Interrupt enable executes (`irq_enabled` logged).
- Register programming reads as expected on FAIL (`INTR_CNTL=0x400004`, `SDW_EN=1`, `FRAME=0xc`).
- `ACP_EXTERNAL_INTR_STAT` reads **0** on instrumented snapshots after enable, bringup, and D0.
- **No** `irq_handler_enter`, **no** `irq_thread_enter`, **no** `ping_irq`, **no** `queue_work` before RT721 timeout.
- **No** bus `UNATTACHED→ATTACHED` or `completion()` in the wait window.
- RT721 `-110` occurs **after** the above; it is not the first failure.
- TAS2783, PipeWire, and userspace rebind are not required to reproduce the kernel witness path.

---

## Not yet demonstrated (do not over-claim)

| Statement | Why it is not proven |
|-----------|----------------------|
| Hardware never asserts the interrupt | Only point-in-time STAT reads + absence of handler in window |
| Interrupt asserted later than observation window | No STAT polling; PASS trace may differ |
| Missing prerequisite prevents first interrupt | Open box at HW boundary; needs PASS diff or programming guide |
| Register values differ on PASS | FAIL reads look programmed; PASS not yet captured with same probes |

---

## Golden diff (primary experimental goal)

Same machine, kernel, instrumentation. **First expected divergence:** `ACP_EXTERNAL_INTR_STAT` and IRQ handler.

| Probe | PASS (target) | FAIL (0015) |
|-------|---------------|-------------|
| `manager_reset` | ✓ | ✓ |
| `init_sdw_manager` | ✓ (`ret=0`) | ✓ (`ret=0`) |
| `enable_sdw_manager` | ✓ (`ret=0`) | ✓ (`ret=0`) |
| `irq_enabled` | ✓ | ✓ |
| `intr_cntl_post_enable` | same | `0x400004` |
| `sdw_en_post_resume` | same | `0x1` |
| `clk_frame` | same | `0xc` |
| `device_state_D0` | same | `ret=0` |
| `ACP_EXTERNAL_INTR_STAT` | **≠0 (or changes)** | **0** |
| `irq_handler_enter` | ✓ | ✗ |
| `ping_irq` | ✓ | ✗ |
| `queue_work` | ✓ | ✗ |
| `completion()` | ✓ | ✗ |
| RT721 | OK | timeout (`-110`) |

One PASS row filling the left column is worth more than additional FAIL traces.

---

## Ruled-out root-cause layers

| Layer | Rationale |
|-------|-----------|
| RT721 codec PM | Waits on `initialization_complete()`; never woken |
| TAS2783 / FW | Downstream of missing enumeration |
| SoundWire `bus.c` | Cannot ATTACH without manager notification |
| Incomplete `amd_resume_runtime()` | Full sequence observed on 0015 |

---

## Instrumentation policy (frozen)

> **Each new patch must answer exactly one binary question.**

Questions already answered — **no default 0008**:

| Binary question | Answer | Patch / run |
|-----------------|--------|-------------|
| Does `manager_reset` run on resume? | Yes | 0003 |
| Are IRQs re-enabled after reset? | Yes | 0004 |
| Is `STAT=0` immediately after enable? | Yes | 0005 / 0013 |
| Is S2 (STAT≠0, no handler)? | No on 0013 | 0005 |
| Are block registers programmed on FAIL? | Yes | 0006 / 0014 |
| Does full kick sequence run (`ret=0`)? | Yes | 0007 / 0015 |
| Does IRQ handler run before timeout? | No on FAIL | 0004–0005 |

If a proposed patch does not eliminate one concrete hypothesis, do not add it.

---

## Attachments (when submitting)

1. `kmsg-phase6-window.log` — FAIL run 0015
2. Same — PASS run (TBD)
3. `./scripts/phase6-experiment.sh sm` output for both
4. Optional: `./scripts/phase6-state-machine.sh RUN_FAIL RUN_PASS`

---

## Suggested upstream title

> ACP70 SoundWire: s2idle resume completes manager re-init but no IRQ before RT721 timeout (ASUS PX13)

## Suggested ask

> Please advise whether a step is missing after `device_state_D0` on ACP70 `POWER_OFF` resume, or whether this matches a known HW/FW sequencing requirement. PASS kernel trace with identical instrumentation available on request / follow-up.

---

## While waiting for PASS

This draft is valid **without PASS** (scenario 2). See [UPSTREAM-STRATEGY.md](UPSTREAM-STRATEGY.md):

- **Scenario 1:** PASS + FAIL golden diff (ideal)
- **Scenario 2:** FAIL only, break localized — **submittable now**
- **Scenario 3:** N/N FAIL — strengthens reproduction

If no kernel PASS after ≥20 masked-rebind attempts, document scenario 3 and reframe the upstream ask (do not weaken the report).

**PASS hunt:** [UPSTREAM-STRATEGY.md#pass-hunt-protocol-bounded-effort](UPSTREAM-STRATEGY.md#pass-hunt-protocol-bounded-effort)
