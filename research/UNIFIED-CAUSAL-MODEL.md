# Unified causal model — suspend/resume SmartAmp (PX13)

English (canonical). **Single investigation thread** as of **2026-07-12**.

> **Rule for upstream (ALSA / AMD):** keep **demonstrated facts**, **strong inferences**, and **not yet demonstrated** strictly separate. This document labels each claim.

**Investigation mode:** state-transition guided (not symptom chasing). Each arrow in the causal chain is independently falsifiable.

**Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`  
**Active protocol:** [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md)  
**PCM framing:** [PCM2-investigation-framing.md](PCM2-investigation-framing.md)

---

## Branch A / Branch B (July 2026)

| Branch | Objective | Priority |
|--------|-----------|----------|
| **A — Make it work** | Audio after S2 without reboot | **P0** — [MAKE-IT-WORK.md](../research/MAKE-IT-WORK.md) |
| **B — Root cause** | Upstream-clean explanation (ACP IRQ delivery) | **P1** — this document |

**KPI (unchanged):** `systemctl suspend` → resume → Speaker / PCM2 OK.

Investigation reduced the search space; it did not replace the product goal.

**We are no longer primarily chasing a TAS2783 codec bug.** State-based investigation localized the break (C1: delivery before ACP handler). **Next P0 question (Branch A):** what **minimal intervention** restores ATTACHED → audio after S2?

**Demonstrated for this cycle (codec layer only):**

```text
resume
   ↓
status != ATTACHED              [observed]
   ↓
skip_io_init                    [observed]
   ↓
no request_firmware_nowait()    [observed]
   ↓
fw_dl_task_done == false        [observed]
   ↓
hw_params wait timeout          [observed]
   ↓
-EINVAL                         [observed — Q1]
```

**Not demonstrated:** the **first** break in the PM → manager → enumeration → ATTACHED ladder. Do **not** assume `manager_reset` is the root site without Q3 instrumentation.

---

## Question tree (layers)

```text
Q1   hw_params → -EINVAL                    [closed ~100%]
Q2   FW async never started                  [closed ~90–95% this cycle]
Q2.5 io_init never ran (status != ATTACHED)  [closed this cycle]
Q3   first missing SoundWire re-attach step  [OPEN — P0]
```

See [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) (Q3 protocol).

---

## Demonstrated downstream chain (2026-07-12)

```text
status != ATTACHED                              [observed]
    ↓
tas_update_status → skip_io_init                [observed]
    ↓
no request_firmware_nowait()                    [observed]
    ↓
no fw_ready()                                   [observed]
    ↓
hw_params wait (~3 s) → timeout                 [observed]
    ↓
tas_sdw_hw_params() → -EINVAL                   [observed — Q1]
    ↓
Dummy Output                                    [consequence]
```

**Correlated same-boot (observed, causal order open):**

- `resume: initialization timed out` / PM `-110` on `:8` and `:b`
- `master_port OK`, port programming succeeds — **master/bus programming alive** while slave init incomplete

**Strong inference:** break is in **slave initialization / re-attach protocol** after resume, not in TAS2783 FW async and likely not a dead SoundWire link.

**Open (Q3):** first transition that does not occur — see models A/B/C in [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md).

Phase 6–8 (ACP IRQ) remains a **candidate** in the manager/IRQ ladder; **not same-boot correlated** with Q2 witness yet.

---

## One thread, many perspectives

What looked like separate lines (IRQ, SoundWire, PCI, firmware, PipeWire, rescue) was **layer elimination** converging on one observable failure. They are not independent hypotheses — they are **different altitudes on the same chain**.

Logical dependency now demonstrated:

```text
ATTACHED  →  io_init  →  fw_ready  →  fw_dl_success
```

If ATTACHED never arrives, the entire downstream ladder is **explained without further codec investigation**.

**Three questions:**

| # | Question | Status |
|---|----------|--------|
| **Q1** | Which function returns `-EINVAL` first? | **Closed ~100%** — `tas_sdw_hw_params()` / `:8` |
| **Q2** | Does async FW start before hw_params? | **Closed ~90–95%** — never attempted this cycle |
| **Q2.5** | Why no `io_init`? | **Closed this cycle** — `status != ATTACHED` → skip |
| **Q3** | First missing SoundWire re-attach transition? | **OPEN — P0** — [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) |

---

## Demonstrated facts (maintainer-safe)

These may be cited as **facts** in upstream mail.

| # | Fact | Evidence |
|---|------|----------|
| F1 | **Dummy Output is not the root cause** | Direct `aplay -D hw:1,2` fails; Dummy follows ALSA |
| F2 | **PipeWire is not the root cause** | Same failure with PW stopped |
| F3 | **PCI enumeration alone is not the fix** | remove/rescan, rebind, reload, FLR (when possible), runtime PM — all reconverge to PCM2 EINVAL |
| F4 | **SoundWire bus is not dead post-resume** | PCM0 (RT721, same card) accepts `hw_params` |
| F5 | **Failure is pre-stream** | Fails at `set_params`; no DMA, no first sample |
| F6 | **Controlled experiment on machine** | Same kernel, resume, PCI, ACP, card, process — only codec path differs (RT721 vs TAS2783) |
| F7 | **Rejecting function is `tas_sdw_hw_params()` on UID `:8`** | `fw download wait timeout` → `playback without fw download` → ASoC -22 on tas2783-codec — [experiments/pcm-dual-path-trace-20260712.md](experiments/pcm-dual-path-trace-20260712.md) |
| F8 | **Historical FW logs = same site** | Track A messages map to `tas2783-sdw.c` ~906 + patch 0007 wait path |
| F9 | **Phase 6–8 (ACP IRQ path)** | STAT1 pending, no handler in FAIL runs; downstream OK if worker forced (0006a) — **not linked to F7 in same-boot proof** |
| F10 | **Not capability shrink** | S0/S2 dump-hw-params identical (S16, 48k, 2ch) |
| F11 | **Not ALSA core / soc_pcm_check_hw_cfg** | ASoC error names codec DAI explicitly |
| F12 | **No observable FW async start before hw_params timeout (2026-07-12 cycle)** | No `io_init` / `nowait` / `fw_ready`; `success=0 done=0` at wait — [experiments/q2-fw-trace-witness-20260712.md](experiments/q2-fw-trace-witness-20260712.md) |
| F13 | **Resume init timeout on both TAS2783 UIDs** | `initialization timed out` / PM -110 on `:8` and `:b` same cycle |
| F14 | **Slaves UNATTACHED when codec recovery paths skip** | `status=0` → `skip_reinit` / `skip_io_init`; no `hw_params reinit` |
| F15 | **AMD manager_reset + D0 bring-up complete on failing resume (2026-07-12)** | PHASE6 resume_enter → manager_reset → init/irq/D0 all ret=0 — [experiments/q3-sdw-reattach-witness-20260712.md](experiments/q3-sdw-reattach-witness-20260712.md) |
| F16 | **No ATTACHED re-attach observed after manager_reset (2026-07-12)** | No `state_change new=ATTACHED` / `fn=completion` post-reset |
| F17 | **STAT1=0x4 post-reset; Q3.1 C1 closed on c1-test boot** | intr_decode + `/proc/interrupts` delta=0 + `handler_since_pm=0` — [experiments/q3.1-c1-boundary-witness-20260712.md](experiments/q3.1-c1-boundary-witness-20260712.md) |
| F18 | **Legacy ACP_PCI_IRQ not accounted post-s2idle while STAT1 pending** | IRQ 160 sum 64→64; handler not entered since suspend (same run) |

Facts F15–F18 from Q3.1 c1-test (boot `2ed67fbb`). F9 Phase 6–8 now **correlated same-boot** with F17–F18.

---

## Ruled out (high confidence)

| Layer | Why ruled out |
|-------|---------------|
| PCI broken | PCM0 works; full remove/rescan unchanged |
| SoundWire enumeration dead | PCM0 + attached TAS2783 in sysfs |
| ACP / SOF hung globally | Card enumerates; SimpleJack path OK |
| WirePlumber / Dummy | Symptom only (F1) |
| Standard driver re-init paths | Rescue/bruteforce converge to same EINVAL (F3) |
| DMA / playback-time IRQ | F5 |
| ALSA constrain / soc_pcm_check_hw_cfg | F11 — 2026-07-12 trace |
| Capability shrink | F10 |
| DAPM-only rejection | No DAPM error; codec FW path failed first |

---

## Q2 witness — codec vs bus boundary (2026-07-12)

**Demonstrated this cycle:**

```text
status != ATTACHED
    ↓
no observable tas_io_init()
    ↓
no observable request_firmware_nowait()
    ↓
fw_dl_task_done stays false
    ↓
hw_params wait → timeout → -EINVAL
```

`skip_io_init` / `skip_reinit` are **observed branch outcomes**, not asserted root causes.

**Not demonstrated (pre-Q3):** which layer fails re-attach (AMD manager vs SoundWire core vs ASoC machine vs IRQ interaction).

**Q3 update (2026-07-12, same boot):** re-attach bounded — no ATTACHED observed post `manager_reset`; full Q1–Q2 chain follows. **Q3.1 open:** bisect STAT1=0x4 → ATTACHED (C1–C5). See [q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md](q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md).

| Level | Q3.1 status this cycle |
|-------|------------------------|
| **Observed** | STAT1=0x4; manager_reset; no ATTACHED; init -110; Q1–Q2 downstream |
| **Strong inference** | IRQ→worker unlike S0 same boot |
| **Not demonstrated** | First break = ACP handler — needs C1 witnesses (`/proc/interrupts`, `handler_since_pm`) |

**Q3.1 C1 update (c1-test 2026-07-12):** C1 **closed as fact** — `handler_since_pm=0`, IRQ 160 delta=0, STAT1=0x4 @ +51 ms. Break class: **delivery before `acp63_irq_handler()`**. Witness: [experiments/q3.1-c1-boundary-witness-20260712.md](experiments/q3.1-c1-boundary-witness-20260712.md). **0006a** remains optional causal retest, not next P0.

Full witness: [experiments/q2-fw-trace-witness-20260712.md](experiments/q2-fw-trace-witness-20260712.md)

### H1–H4 (this cycle)

| ID | Verdict |
|----|---------|
| H1 | Supported — no observable `io_init` before timeout |
| H2 | Ruled out — no `nowait` |
| H3 | Ruled out — no `fw_ready enter` |
| H4 | Ruled out — no post-invalidate `success=1` |

### Inferred chain (IRQ — not same-boot proven)

```text
IRQ not delivered → worker/init delayed → attach incomplete → … → EINVAL
```

**Consequence (not cause):** `SDW: Invalid device for paging :0` after timeout/deprepare.

---

## Natural control group (PCM0 vs PCM2)

The machine provides a **paired experiment** every resume:

| Held constant | Varies |
|---------------|--------|
| kernel, resume event, PCI, ACP, ALSA card, `aplay`, time | **RT721 (pcm0)** vs **TAS2783×2 (pcm2)** |

**Protocol:** instrument **both paths in one run**; find the **first divergence point** in the call chain — more informative than tracing only the failing PCM.

```bash
sudo resolution/scripts/pcm-hwparams-trace.sh --label S2 --dual-path
```

See [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md) § Dual-path trace.

---

## Branch status (all repo lines)

| Branch | Role in unified model | Status | Entry |
|--------|----------------------|--------|-------|
| **Track PCM2** | Q1 + Q2 codec ladder closed | **Closed** | [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md) |
| **Q2.5 SDW re-attach (Q3 / Q3.1)** | Re-attach bounded; IRQ checkpoint bisect | **Active P0 — Q3.1** | [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) |
| Phase 6–8 | ACP delivery candidate; 0006a causal | **Correlate with Q3.1** — not assumed root | [frozen/upstream-proof/](frozen/upstream-proof/) |
| Track A (FW `:8`) | Historical manifestation / same chain altitude | **Absorbed** — do not fork | [track-A-serie-b-suspend.md](track-A-serie-b-suspend.md) |
| Track B (capture -22) | Unrelated playback blocker | **Closed** | [track-B-capture-pin4.md](track-B-capture-pin4.md) |
| Track C (webcam) | Independent USB/media | **Parallel P3** | [tracks/TRACK-C-WEBCAM-MEDIA0.md](tracks/TRACK-C-WEBCAM-MEDIA0.md) |
| Track D (PipeWire) | Aggravator, not root | **Mitigated** | [track-D-userspace-pipewire.md](track-D-userspace-pipewire.md) |
| `resolution/lab` | S2→S3 edges (recovery) | **Paused** — no stable edge | [../resolution/README.md](../resolution/README.md) |
| `resolution/bruteforce` | Negative result: rebuild ≠ fix | **Frozen** | [../resolution/bruteforce/README.md](../resolution/bruteforce/README.md) |
| `resolution/rescue` | Negative result: levels A–D | **Paused** | [../resolution/rescue/README.md](../resolution/rescue/README.md) |
| `resolution/salvage` | Teardown methodology | **On hold** | [../resolution/salvage/README.md](../resolution/salvage/README.md) |
| Upstream series B | **0003** — **blocked on ATTACHED-never-returns scenario**; retest if attach succeeds | **On hold** | [../upstream/series-B-firmware/](../upstream/series-B-firmware/) |

**Do not open new branches.** Next: **Q3.1 Phase A** — C1 with `/proc/interrupts` + `handler_since_pm`; **0006a only after** bisect narrows.

---

## Q3.1 — active bisect

See [q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md](q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md).

### Priority 1 — Q3.1: STAT1=0x4 → ATTACHED

Instrument C1–C5 on one boot. Language: **not observed** until probe covers the site.

Do **not** invest further in TAS2783 except keeping existing probes.

---

## What we stopped doing

| Stopped | Reason |
|---------|--------|
| "Does audio work?" as unit | Replace with "does PCM2 accept hw_params?" |
| Rescue / bruteforce new sequences | Negative result — same EINVAL |
| Chasing Dummy Output | F1 |
| Treating IRQ as proven root of EINVAL | Evidence / explanation separation |
| Phase 6–8 identical FAIL traces | Saturated — frozen |
| Deep TAS2783 FW / async ladder work | Q2 closed — explained by missing ATTACHED |

---

## Series B (0003) — reframed

**0003 is not wrong.** It assumes:

```text
resume → slave ATTACHED → invalidate → fw_reinit / io_init
```

This machine’s failure mode:

```text
resume → slave never ATTACHED → 0003 paths never entered
```

That explains why 0003 may help on platforms where attach succeeds but FW state is stale, and **does nothing here** where attach never completes. Retest 0003 only when a witness shows `status=ATTACHED` post-resume.

---

## Upstream design note (observed behaviour)

On the Q2 witness cycle:

1. `PM: failed to resume: error -110` — driver reports slave resume failure.
2. Later: `status=0` (UNATTACHED) — `skip_io_init` / `skip_reinit`.
3. Later still: `tas_sdw_hw_params()` runs and **waits ~3 s** for firmware completion that was never started.

Approximate control flow:

```c
/* update_status / resume paths */
if (!attached)
    skip_io_init();

/* hw_params — later, userspace playback */
wait_for_completion_timeout(...);  /* fw_dl_task_done */
if (!fw_dl_success)
    return -EINVAL;
```

If UNATTACHED is the known state, proceeding to a blocking FW wait may be **undesirable** (symptom masking vs early fail). Worth raising upstream separately from root-cause localization — does not change Q2.5 priority.

---

## What we do instead

### Branch A (P0) — make it work

See [MAKE-IT-WORK.md](MAKE-IT-WORK.md). **Recommended next:** W1 trial **0006a** (`build-phase7.sh --experiment validate-manager-mask`).

### Branch B (P1) — root cause / upstream

C1 closed (c1-test). Package F17–F18 + Phase 8.1 for maintainer mail. No new IRQ trace unless W1 fails.

### Conditional

Series B **0003** when ATTACHED returns (often after W1).

Upstream mail (Branch B): attach Q1–Q2 witnesses + separate Phase 8 IRQ bundle — see [phase-6/UPSTREAM-REPORT-DRAFT.md](phase-6/UPSTREAM-REPORT-DRAFT.md).

---

## Definition of done

| Gate | Criterion |
|------|-----------|
| **Branch A — user fix** | ≥6/6 S2 OK in `validation/fw-matrix.csv` **← primary KPI** |
| Q1–Q2 closed | ✅ 2026-07-12 |
| Q3 / Q3.1 C1 | ✅ Re-attach bounded; handler delivery gap (c1-test) |
| **Branch B — upstream** | Maintainer-ready fact bundle; clean fix optional |

---

## Related

| Doc | Role |
|-----|------|
| [JOURNEY.md](JOURNEY.md) | Historical timeline |
| [INVESTIGATION-INDEX.md](INVESTIGATION-INDEX.md) | Track index (updated) |
| [experiments/pcm-dual-path-trace-20260712.md](experiments/pcm-dual-path-trace-20260712.md) | **Q1 closed** |
| [experiments/q2-fw-trace-witness-20260712.md](experiments/q2-fw-trace-witness-20260712.md) | **Q2 closed (cycle)** |
| [MAKE-IT-WORK.md](MAKE-IT-WORK.md) | **Branch A P0** |
| [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) | Branch B — Q3/Q3.1 |
| [q2-fw-resume/CONSOLIDATION.md](q2-fw-resume/CONSOLIDATION.md) | Q2 handoff + 0003 reframe |
| [q2-fw-resume/HYPOTHESES.md](q2-fw-resume/HYPOTHESES.md) | H1–H4 matrix |
| [tas2783-fw_dl_success-map.md](tas2783-fw_dl_success-map.md) | Q2 code map |
| [pcm-hwparams-code-path.md](pcm-hwparams-code-path.md) | Static EINVAL map |
| [phase-6/KNOWN-FACTS.md](phase-6/KNOWN-FACTS.md) | IRQ boundary facts (F9 detail) |
| [../docs/PROJECT-STATE.md](../docs/PROJECT-STATE.md) | Executive state |
