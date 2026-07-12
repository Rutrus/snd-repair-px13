# Q3 SoundWire re-attach witness — 2026-07-12

**Machine:** ASUS ProArt PX13, kernel `7.0.0-27-generic`  
**Boot:** same session as [q2-fw-trace-witness-20260712.md](q2-fw-trace-witness-20260712.md)  
**Collect:** `validation/q3-sdw-reattach/after-resume-103319-20260712T105408.log`  
**Modules:** PHASE6 (0002–0007) + TAS2783Q2 trace (installed pre-capture)

---

## Question (Q3)

What is the **first transition** in the SoundWire re-attach ladder that does not occur after resume?

---

## Resume timeline (observed, one S2 cycle ~10:30–10:33)

| Time (local) | Transition | Label |
|--------------|------------|-------|
| 10:33:19.374 | `PHASE6 ctx=amd fn=resume_enter` resume=1 | observed |
| 10:33:19.374 | `fn=manager_reset` resume=1 | observed |
| 10:33:19.375 | `state_change` ATTACHED→UNATTACHED (TAS2783 :b/:8, RT721) reason=manager_reset | observed |
| 10:33:19.376–378 | AMD bring-up: init_sdw_manager, irq_enabled, D0, intr_stat post steps — all ret=0 | observed |
| 10:33:19.379 | PHASE7 `intr_decode post_delay` STAT1=0x4 (IRQ latched) | observed |
| 10:33:19.380+ | **No** `irq_thread_enter` / `ping_irq` / `queue_work` / `handle_status` with resume=1 | **missing** |
| 10:33:19.380+ | **No** `state_change` UNATTACHED→ATTACHED / `fn=completion` | **missing** |
| 10:33:19.381 | RT721 `wait_init_timeout` + PM -110; TAS2783 `initialization timed out` (:8/:b) | observed |
| 10:33:19.375 | TAS2783Q2 `update_status status=0` + `skip_io_init` | observed |
| 10:33:25+ | TAS2783 `:8` hw_params FW wait timeout → -EINVAL | observed (downstream) |

**Analyzer (corrected ladder):** first missing step = **AMD IRQ path post-reset (resume=1)**.

---

## Contrast — S0 playback same boot (~10:29:57)

Before suspend, IRQ worker runs normally:

```text
irq_thread_enter → ping_irq → queue_work → handle_status (st1=ATTACHED)
→ state_skip reason=already_attached
```

Same boot, same modules — worker path **works at runtime**, **absent after system resume manager_reset**.

---

## Break site (this cycle, engineering estimate ~85–90%)

```text
manager_reset + AMD D0 bring-up complete
    ↓
STAT1=0x4 latched (post 50ms decode)
    ↓
[MISSING] amd_sdw_irq_thread / handle_status / enumeration → ATTACHED
    ↓
initialization_complete never signaled
    ↓
slaves stay UNATTACHED → skip_io_init → Q2/Q1 chain
```

**Not claimed:** root cause inside `manager_reset` itself — reset and detach are **expected**.  
**Supported:** re-attach **IRQ/enumeration path** does not run (or does not complete) before slave PM times out.

Candidate models (non-exclusive until bisect):

| Model | Fit this cycle |
|-------|----------------|
| A — init timeout waiting for ATTACHED | Yes (symptom) |
| B — enumeration never reaches ATTACHED | Yes (no state_change post-reset) |
| C — ATTACHED without callback | No evidence |

Correlates with Phase 6–8 ACP IRQ narrative (STAT pending) but **same-boot PHASE7 intr_decode present here** — next step is bisect **ACP MSI/thread wake vs AMD worker scheduling** after system resume.

---

## Definition of done — partial

| Gate | Status |
|------|--------|
| First missing transition localized | **Yes** — IRQ worker / handle_status post manager_reset |
| Fix validated | No |
| Upstream-ready timeline | This doc + collect log |

---

## Reproduce

```bash
./scripts/q3-sdw-reattach-collect.sh --label after-resume
./scripts/q3-sdw-reattach-analyze.sh
```

Requires PHASE6 + TAS2783Q2 modules (`./scripts/build-q3-trace.sh`, reboot).
