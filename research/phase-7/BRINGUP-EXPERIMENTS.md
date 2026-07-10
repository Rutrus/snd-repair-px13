# Phase 7 — ACP70 bring-up experiments

English (canonical). **Active intervention** after Phase 6 observation is exhausted.

| Phase | Mode | Question |
|-------|------|----------|
| **Phase 6** | Observation | *What happens?* — **closed** on FAIL (0015+) |
| **Phase 7** | Experimentation | *What change makes STAT / IRQ appear?* |

**Entry condition:** Full software kick sequence runs; `ACP_EXTERNAL_INTR_STAT=0`; no handler (FACT 12). See [../phase-6/KNOWN-FACTS.md](../phase-6/KNOWN-FACTS.md).

**Exit condition:** First patch that changes observable behaviour (STAT≠0, handler runs, or ATTACHED) — not necessarily a production fix.

---

## Rules (carry forward from Phase 6)

1. **One binary question per patch/commit** — e.g. *"Does a 20 ms delay after D0 make STAT≠0?"*
2. **No horizontal `printk()`** — outcome probes only if needed to score the experiment (STAT read + pass/fail line).
3. **Not a production fix** until mechanism is understood; experiments may be `#ifdef` or boot param gated.
4. **RT721 / TAS2783 / bus.c frozen** — intervene only in `amd_manager.c` / ACP path unless experiment proves otherwise.
5. **Each run:** `phase6-hunt.sh post-reboot` → suspend → `post-suspend` — same witness as Phase 6.

---

## Open hypotheses (post-D0)

After `device_state_D0`, `STAT=0` implies one of:

| # | Hypothesis | Phase 7 experiment |
|---|------------|-------------------|
| H1 | Missing **kick** after D0 | A — re-run bring-up steps |
| H2 | Missing **external event** (ACPI/PME/clock domain) | D + register/code diff vs reference |
| H3 | **Timing** — Linux sequence too fast or wrong order | B — reorder / delay |
| H4 | Event occurs but **IRQ path not taken** | C — bounded STAT poll + manual process |

---

## Experiment A — Recoverable if bring-up repeated?

**Question:** If we **manually repeat** steps the driver already ran, does the first STAT bit or slave activity appear?

Candidates (one per patch, not combined):

| Patch id | Intervention | Binary question |
|----------|--------------|-----------------|
| `0001-double-init` | Call `amd_init_sdw_manager()` again after D0 | STAT≠0 or handler? |
| `0002-re-enable-manager` | `amd_disable_sdw_manager` → `amd_enable_sdw_manager` after D0 | STAT≠0? |
| `0003-re-frameshape` | Second `amd_sdw_set_frameshape()` after D0 | STAT≠0? |
| `0004-clk-resume-retry` | Re-pulse `ACP_SW_CLK_RESUME_CTRL` if applicable | STAT≠0? |

**Pass criteria:** Any of `intr_stat_post_D0≠0`, `irq_handler_enter`, `ping_irq`, `UNATTACHED→ATTACHED` within RT721 wait window.

**Fail criteria:** Identical to baseline 0015 → hypothesis rejected for that intervention.

---

## Experiment B — Ordering / timing

**Question:** Is the break **sequencing or delay**, not missing code?

| Patch id | Intervention | Binary question |
|----------|--------------|-----------------|
| `0005-delay-after-D0` | `msleep(20)` (or 50) after `device_state_D0` before return | STAT≠0 after delay? |
| `0006-delay-before-enable` | Delay between `init_sdw_manager` and `enable_sdw_manager` | STAT≠0? |
| `0007-enable-before-reset` | **Risky** — swap or split reset vs enable (fork path only) | Any change vs baseline? |

Start with **0005** (lowest risk, highest frequency class for suspend/resume bugs).

---

## Experiment C — STAT poll / manual process (IRQ bypass test)

**Question:** Does hardware **ever** set STATUS bits if we wait longer or poll, even when IRQ does not fire?

Not a fix — tests H4 vs H1/H3.

Sketch (observation + minimal intervention):

```text
after D0:
  for i in 0..200ms step 10ms:
    read ACP_EXTERNAL_INTR_STAT
    read ACP_SW_STATE_CHANGE_STATUS_*
    if any non-zero → log once, optionally schedule amd_sdw_irq_thread work
```

**Binary question:** Does STAT or STATE_CHANGE become non-zero within 200 ms on FAIL when IRQ never fired?

- **Yes, STAT only** → S2-like routing or mask (revisit IRQ enable path).
- **Yes, STATE_CHANGE only** → external INTR mapping issue.
- **No** → hardware not generating activity in that window (H1/H2).

---

## Experiment D — Cross-platform reference

**Question:** Is this **PX13-specific** (BIOS/ACPI/OEM) or **ACP70 family**?

| Action | Value |
|--------|-------|
| Same kernel + same 0003–0007 patches on **another ACP70 machine** | PASS / FAIL / same trace |
| Compare ACPI `_PS0` / `_PRW` / SoundWire nodes vs PX13 | OEM diff list |
| Same PX13, **older kernel** or **windows driver sequence** (docs only) | Missing step list |

No code required for first pass — blocks Experiment A–C if another ACP70 passes with identical trace.

---

## Code review target (not print — compare)

Search `amd_manager.c` / ACP headers for steps that might be **Windows-only** or **boot-only** but absent on resume:

- Soft reset / `ACP_RESET` / manager re-init after power domain
- Clock mux / `ACP_CLK` after D0
- PME / wake unmask timing vs `device_state_D0`
- Explicit ping / autonomous enumeration start (Intel has `config_update`; AMD may have undocumented register)

Deliverable: short table *"register / step present on probe, absent on POWER_OFF resume"* — feeds patch choice.

---

## Suggested order

```text
1. Submit Phase 6 upstream draft (scenario 2/3)     ← parallel, not blocking
2. Experiment D (if second ACP70 available)         ← highest leverage
3. Experiment B: 0005 delay-after-D0                ← cheap timing test
4. Experiment A: 0002 or 0001                       ← recoverability
5. Experiment C                                     ← only if A/B unchanged
```

---

## Patch layout

```text
research/phase-7/proposed/
  0005-delay-after-d0.patch
research/phase-7/experiments/
  0005-delay-after-d0.md          ← falsification criteria + sweep
scripts/build-phase7.sh           # Phase 6 base + ONE experiment
```

```bash
/home/rutrus/snd_repair/scripts/build-phase7.sh --experiment delay-after-d0 [--delay 20]
```

Each build applies **baseline 0003–0007 + exactly one** Phase 7 patch. Use `build-phase7.sh`, not `build-phase6-amd-trace.sh`, while an experiment is active.

---

## Precedent (amd_manager resume)

No `msleep` / `usleep_range` on AMD SDW manager resume path in-tree; only `read_poll_timeout` on register polls. Delay experiment is **exploratory**, not mirroring existing AMD code.

---

## Progress metric

| Metric | Phase 6 | Phase 7 |
|--------|---------|---------|
| Success | Localized break | **First behavioural change** |
| Another identical FAIL trace | +1 to N | **Wasted run** |
| Acceptable outcome | PASS capture | STAT≠0 **or** handler **or** ATTACHED |

---

## Relation to Phase 6

Phase 6 remains frozen. Phase 7 patches are **behaviour-changing experiments** on top of the same witness instrumentation. Do not merge experiment patches into Phase 6 trace series without renaming (phase7-*).

Next: implement `0005-delay-after-D0` when ready to run first experiment.
