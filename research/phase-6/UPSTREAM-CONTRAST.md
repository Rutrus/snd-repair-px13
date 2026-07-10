# Phase 6 — Upstream contrast target (PASS vs FAIL)

English (canonical). **Do not add horizontal AMD instrumentation** until this contrast exists or new evidence breaks a ruled-out fact.

**FAIL witness:** run **0015** (`resume=1`, 0003–0007). See [KNOWN-FACTS.md](KNOWN-FACTS.md) FACT 11–12.

**Submit draft (usable before PASS):** [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md)

---

## What is demonstrated (maintainer-safe)

> After s2idle resume on AMD ACP70 (`POWER_OFF` path), `amd_resume_runtime()` runs the full instrumented sequence (`manager_reset` through `device_state_D0`, all observed `ret=0`). Block control registers read as programmed (`INTR_CNTL`, `SDW_EN`, `FRAME`). On the instrumented reads immediately after enable, bringup, and D0, **`ACP_EXTERNAL_INTR_STAT` is 0**. **No IRQ handler activity** is observed during the ~5 s window before RT721 `wait_for_completion_timeout()` returns `-110`. No SoundWire re-enumeration log activity occurs in that window.

## What is NOT demonstrated

Do **not** claim:

- *"Hardware never asserts an interrupt."*
- *"ACP70 is broken."*
- *"Register programming is wrong on FAIL"* (reads match expected programmed state).

Those require PASS contrast, HW docs, or silicon/FW analysis.

---

## Hardware boundary (open box)

```text
software (demonstrated complete on FAIL)
──────────────────────────────────────
resume → manager_reset → … → device_state_D0

hardware boundary  ═══════════════════
????  (first event that should set STAT / STATE_CHANGE)

interrupt path (observed absent on FAIL)
──────────────────────────────────────
STAT=0 → no handler → no irq_thread → no queue_work
      → no ATTACHED → no completion → RT721 -110
```

---

## Gold table (same machine, kernel, patches)

| Step | FAIL (0015) | PASS (target) |
|------|-------------|---------------|
| `resume=` | 1 | 1 |
| `manager_reset` | ✓ | ✓ |
| All kick probes | `ret=0` | `ret=0` |
| `INTR_CNTL` / `EN` / `FRAME` | programmed | programmed (expect same) |
| `intr_stat_post_D0` | **0** | **≠0** |
| `irq_handler_enter` | ✗ | ✓ |
| `ping_irq` | ✗ | ✓ |
| `queue_work` | ✗ | ✓ |
| `UNATTACHED→ATTACHED` | ✗ | ✓ |
| `completion()` | ✗ | ✓ |
| RT721 | `-110` | OK |

One diff row (`STAT` + handler) is worth more than further FAIL-only traces.

---

## Ruled out (high confidence)

| Layer | Reason |
|-------|--------|
| RT721 | First waiter on `initialization_complete()`; never signalled |
| TAS2783 | Downstream of missing enumeration |
| `bus.c` core | No ATTACHED without manager notification |
| `amd_resume_runtime()` sequencing | Full path runs; no early `return` on FAIL (0015) |
| S2 (STAT≠0, no handler) | Ruled out on 0013 |

---

## Hypothesis weights (investigation, not proven)

| Hypothesis | Weight |
|------------|--------|
| ACP70 manager / HW resume sequencing (ACP-specific) | **~90%** |
| SoundWire protocol after IRQ | ~7% |
| Codec / bus core | ~3% |

---

## Instrumentation freeze

**Frozen (no new patches without new question):**

- RT721, TAS2783, `bus.c` — witnesses answered
- AMD 0008+ horizontal register/kick logs — FAIL path sufficient

**Keep installed:** 0003–0007 for PASS capture.

**0008 only if** it answers a *new* question (e.g. missing START/reset-exit on FAIL **and** PASS shows a difference). Not more `ret=0` existence probes.

---

## Capture PASS

```bash
sudo reboot
sudo systemctl mask --runtime px13-audio-rebind.service
./scripts/phase6-experiment.sh arm --notes run-16-pass
systemctl suspend
# verify audio works (not Dummy Output)
./scripts/phase6-experiment.sh sm
```

If intermittent: multiple clean-boot attempts; prioritize **any** PASS with same instrumentation over more FAIL traces.

Compare:

```bash
./scripts/phase6-state-machine.sh RUN_FAIL RUN_PASS
```

---

## Upstream submit checklist

- [ ] FAIL log bundle (0015 window)
- [ ] PASS log bundle (same 0003–0007)
- [ ] Side-by-side `sm` or `matrix` output
- [ ] Machine: ASUS ProArt PX13, ACP70, kernel `7.0.0-27-generic`
- [ ] Wording uses "observed" / "no handler in window" — not "HW never fires"
