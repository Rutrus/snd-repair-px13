# Unified causal model — suspend/resume SmartAmp (PX13)

English (canonical). **Single investigation thread** as of **2026-07-12**.

> **Rule for upstream (ALSA / AMD):** keep **demonstrated facts** and **inferred explanations** strictly separate. This document labels each claim.

**Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`  
**Active protocol:** [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md)  
**PCM framing:** [PCM2-investigation-framing.md](PCM2-investigation-framing.md)

---

## Investigation nature (post-Q2 witness)

**We are no longer primarily chasing a TAS2783 codec bug.** Investigation is **state-based**: the codec is the first visibility point; the open work is **which SoundWire re-attach state transition fails after resume**.

Two hypotheses that looked equally strong before Q2:

| Hypothesis | Status after Q2 witness |
|------------|-------------------------|
| TAS2783 loses / fails firmware reload after resume | **Not primary** — FW download is **never attempted** |
| SoundWire resume stays incomplete | **Leading model** — slave stays UNATTACHED; init timeout observed |

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
| F16 | **No ATTACHED re-attach after manager_reset this cycle** | No `state_change new=ATTACHED` / `fn=completion`; no `irq_thread`/`handle_status` resume=1 post-reset |
| F17 | **STAT1=0x4 latched post-reset but worker absent** | PHASE7 intr_decode post_delay; contrast S0 same boot where worker runs |

Facts F1–F7, F10–F11 from PCM trace. F12–F14 from Q2 trace. F15–F17 from Q3 collect (same boot as F12–F14). F9 independent.

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

**Q3 update (2026-07-12, same boot):** first missing transition = **AMD IRQ worker path after manager_reset** (no `ping_irq`/`handle_status` resume=1; no UNATTACHED→ATTACHED). See [experiments/q3-sdw-reattach-witness-20260712.md](experiments/q3-sdw-reattach-witness-20260712.md).

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
| **Q2.5 SDW re-attach (Q3)** | First missing re-attach transition | **Active P0 — break site ~IRQ worker post-reset** | [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) |
| Phase 6–8 | Remote cause candidate (IRQ boundary) | **Frozen** — correlate same-boot if pursued | [frozen/upstream-proof/](frozen/upstream-proof/) |
| Track A (FW `:8`) | Historical manifestation / same chain altitude | **Absorbed** — do not fork | [track-A-serie-b-suspend.md](track-A-serie-b-suspend.md) |
| Track B (capture -22) | Unrelated playback blocker | **Closed** | [track-B-capture-pin4.md](track-B-capture-pin4.md) |
| Track C (webcam) | Independent USB/media | **Parallel P3** | [tracks/TRACK-C-WEBCAM-MEDIA0.md](tracks/TRACK-C-WEBCAM-MEDIA0.md) |
| Track D (PipeWire) | Aggravator, not root | **Mitigated** | [track-D-userspace-pipewire.md](track-D-userspace-pipewire.md) |
| `resolution/lab` | S2→S3 edges (recovery) | **Paused** — no stable edge | [../resolution/README.md](../resolution/README.md) |
| `resolution/bruteforce` | Negative result: rebuild ≠ fix | **Frozen** | [../resolution/bruteforce/README.md](../resolution/bruteforce/README.md) |
| `resolution/rescue` | Negative result: levels A–D | **Paused** | [../resolution/rescue/README.md](../resolution/rescue/README.md) |
| `resolution/salvage` | Teardown methodology | **On hold** | [../resolution/salvage/README.md](../resolution/salvage/README.md) |
| Upstream series B | **0003** — **blocked on ATTACHED-never-returns scenario**; retest if attach succeeds | **On hold** | [../upstream/series-B-firmware/](../upstream/series-B-firmware/) |

**Do not open new branches.** Next: **Q2.5** — localize SoundWire re-attach after resume; optional same-boot Phase 6 correlation.

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

### Priority 1 — Q3: first missing re-attach transition

**Do not invest further in TAS2783** except keeping existing probes for regression.

Instrument SoundWire manager/core on **one boot** — see [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md):

```text
amd_resume → amd_sdw_irq_thread → sdw_handle_slave_status
    → sdw_initialize_slave → sdw_update_slave_status → ATTACHED → tas_update_status
```

Mark each step observed/missing. Do **not** assume break at `manager_reset`.

### Priority 2 — Series B 0003 (conditional)

Only when ATTACHED returns post-resume.

### Priority 3 — Same-boot IRQ ↔ attach correlation

Phase 6 + Q2/Q2.5 trace on one suspend cycle.

### Priority 4 — Upstream mail (two attachments)

1. **Demonstrated:** Q1 + Q2 witnesses, causal model with fact/inference labels  
2. **Separate:** Phase 6–8 IRQ boundary — not merged as proven cause

---

## Definition of done

| Gate | Criterion |
|------|-----------|
| **Q1 closed** | ✅ `tas_sdw_hw_params()` / `:8` — 2026-07-12 |
| **Q2 closed (cycle)** | ✅ FW async never started — [experiments/q2-fw-trace-witness-20260712.md](experiments/q2-fw-trace-witness-20260712.md) |
| **Q2.5 closed (layer)** | ✅ `io_init` skipped — `status != ATTACHED` this cycle |
| **Q3 closed** | First missing re-attach transition localized, or ATTACHED + PCM2 PASS |
| **User fix** | ≥6/6 real suspend/resume OK in `validation/fw-matrix.csv` without reboot |
| **Upstream** | Patch or maintainer ack with demonstrated fact / inference separation |

---

## Related

| Doc | Role |
|-----|------|
| [JOURNEY.md](JOURNEY.md) | Historical timeline |
| [INVESTIGATION-INDEX.md](INVESTIGATION-INDEX.md) | Track index (updated) |
| [experiments/pcm-dual-path-trace-20260712.md](experiments/pcm-dual-path-trace-20260712.md) | **Q1 closed** |
| [experiments/q2-fw-trace-witness-20260712.md](experiments/q2-fw-trace-witness-20260712.md) | **Q2 closed (cycle)** |
| [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) | **Q2.5 active P0** |
| [q2-fw-resume/CONSOLIDATION.md](q2-fw-resume/CONSOLIDATION.md) | Q2 handoff + 0003 reframe |
| [q2-fw-resume/HYPOTHESES.md](q2-fw-resume/HYPOTHESES.md) | H1–H4 matrix |
| [tas2783-fw_dl_success-map.md](tas2783-fw_dl_success-map.md) | Q2 code map |
| [pcm-hwparams-code-path.md](pcm-hwparams-code-path.md) | Static EINVAL map |
| [phase-6/KNOWN-FACTS.md](phase-6/KNOWN-FACTS.md) | IRQ boundary facts (F9 detail) |
| [../docs/PROJECT-STATE.md](../docs/PROJECT-STATE.md) | Executive state |
