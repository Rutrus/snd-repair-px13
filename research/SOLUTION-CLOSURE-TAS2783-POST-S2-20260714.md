# Solution closure — TAS2783 post-S2 silent playback (PX13)

**2026-07-14** · Branch A · English (canonical)

---

## Executive summary

**Post-S2 internal speaker silence is resolved** with an event-driven second `tas2783_fw_reinit()` on the **first playback `hw_params`** after system sleep. Validated by ear (stereo L+R) via W8 experiment and **upstream candidate module**; reproducible from a clean kernel tree reset + `build-upstream-post-sleep-reinit.sh`.

| Milestone | Status |
|-----------|--------|
| Root cause class | **Resume context** — first `fw_reinit()` before first PCM stream setup; not corrupt FW |
| Fix mechanism | `resume_playback_reinit_pending` → one-shot 2nd `fw_reinit()` in `hw_params` |
| W8 validation | PASS L+R @ 0 ms delay (pipeline hook, not timer) |
| Upstream module | PASS post-S2 + clean reinstall from commit |
| Upstream submission | Patch ready — [patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch](../upstream/patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch) |

Supersedes the **2026-07-12 silent-playback caveat** in [SOLUTION-CLOSURE-KPI-U-20260712.md](SOLUTION-CLOSURE-KPI-U-20260712.md) for **SmartAmp playback after S2** when the upstream candidate module is installed.

---

## Causal chain (final)

```text
S2 resume
  → SoundWire ATTACHED + W2 resume-path fw_reinit()
  → ret=0 but speakers silent (functional failure)

First real hw_params (stream setup)
  → 2nd fw_reinit()  [resume_playback_reinit_pending]
  → stereo audio

Later hw_params on same boot
  → no extra reinit (one-shot flag cleared)
```

**Rejected hypotheses:** corrupt FW, missing `init_seq` (W4), DAPM/FU_MUTE (W3/W4), PipeWire/ALSA routing (jack OK, PCM RUNNING).

**W6 @ 3000 ms:** timing was a **readiness proxy**, not the fix. W8 @ 0 ms favours **audio pipeline context** (first `hw_params`) over a magic delay.

**Do not over-claim:** experiments support “wrong resume context (no active PCM stream yet)”, not exclusively “X milliseconds too early”. Time and context may overlap; W8 discriminates in favour of context.

---

## Investigation narrative (what each experiment proved)

### Ruled out (high confidence)

| Hypothesis | Evidence |
|------------|----------|
| PipeWire / userspace routing | `hw_ptr` advances; ALSA direct; jack OK post-S2; defect isolated to TAS2783 |
| Firmware download failure | `fw_ok=1`, `init_seq` runs, `ret=0` on `fw_reinit` |
| Missing DAPM / FU_MUTE | W3/W4: `POST_PMU`, `FU_MUTE=0`, SDCA readback identical PASS vs FAIL |

### Inflection point — W5 (not W4)

```text
resume → W2 fw_reinit → silence → W5 manual fw_reinit → audio
```

Same function, same code path. The question shifted from “missing register write” to **why identical code works when run later**.

### W6 — “is it time?”

| Delay | Audio |
|-------|-------|
| 0 ms (no 2nd reinit) | FAIL |
| 3000 ms | PASS |

Suggests a temporal component — but does not prove a specific millisecond threshold is the root cause.

### W7 — “or is it context?”

Timestamps show resume is not idle time: W2 uid11/uid8, PipeWire `port_prep`, parallel W6 work, etc. The second `fw_reinit()` is not the same operation when run:

- during bare resume / `update_status`,
- before any PCM open,
- at first `hw_params`,
- or minutes later via debugfs.

### W8 — strongest discriminator

No artificial sleep. First `hw_params` after resume is sufficient for stereo PASS. Upstream-preferred sequence:

```text
resume → W2 → (silence) → first PCM hw_params → 2nd fw_reinit → audio
```

---

## Bug report wording (for ALSA / maintainer)

Use this formulation — evidence-backed, avoids over-claiming timing:

> After an S2 resume, `tas2783_fw_reinit()` invoked from `update_status()` completes successfully (`ret=0`, firmware loaded, `init_seq`, SDCA and DAPM apparently correct), yet the amplifiers remain silent. Running the same `tas2783_fw_reinit()` during the first `hw_params` after resume systematically restores audio. This suggests the defect is not the content of the reinit but the **context** in which it runs within the resume cycle (before vs after the first real playback stream setup).

Full draft: [../upstream/BUG-REPORT-DRAFT.md](../upstream/BUG-REPORT-DRAFT.md)

## What to install (daily driver)

Prerequisites: upstream series **A+B+C** (same as [build-from-upstream.sh](../scripts/build-from-upstream.sh)) + **W1** (0006a IRQ resume) if not already in your kernel build.

```bash
# Clean tree (linux-source-* is gitignored — use reset, not git checkout)
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh

# Post-S2 playback fix (this closure)
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo reboot
```

**Do not combine** with `px13-audio-resume.service` when testing W1+W2 stack ([px13-audio-fix-vs-w1w2.md](experiments/px13-audio-fix-vs-w1w2.md)).

**Experimental stack (W4–W8 traces):** optional for investigation only; production path is `build-upstream-post-sleep-reinit.sh` without enabling `deferred_reinit_*` module params.

---

## Validation (canonical)

```bash
# After reboot — mask PW if EBUSY on direct ALSA
systemctl --user stop wireplumber pipewire pipewire-pulse
systemctl suspend && sleep 5
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -s 1 -l 5   # Left
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -s 2 -l 5   # Right
systemctl --user start pipewire pipewire-pulse wireplumber

# One-shot: second open same boot — no full FW reload storm
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
```

**Pass:** audible tone both channels post-S2; session audio OK after PipeWire restart.

**Persistence gate (recommended):** S2 × 3 with the same procedure.

Automated helper (experimental W8 params — use only if module still has W8 debug):

```bash
sudo ./scripts/w8-context-reinit-test.sh --mode hw-params
```

---

## Investigation timeline (W4 → upstream)

| ID | Result |
|----|--------|
| W4 / W4b | Identical lifecycle readback PASS vs FAIL — not register drift |
| W5 | Manual 2nd `fw_reinit()` restores audio — reproducible |
| W6 | Timer 3000 ms PASS; 0 ms FAIL — time = readiness proxy |
| W7 | ms anchors: W2 ~2.7 s before first `hw_params` |
| W8 | `hw_params` hook @ 0 ms → stereo PASS |
| **Upstream** | `resume_playback_reinit_pending` — PASS + clean reinstall |

Details: [experiments/w8-context-results.md](experiments/w8-context-results.md) · [upstream/upstream-draft-tas2783-post-s2-reinit.md](../upstream/upstream-draft-tas2783-post-s2-reinit.md)

---

## Frozen / parked

| Item | Reason |
|------|--------|
| W6 delay sweep (1500 ms threshold) | Superseded by W8 event hook |
| W8 port-prep / dapm-pmu modes | hw_params sufficient |
| W6 `deferred_reinit_ms=3000` workaround | Fallback until upstream patch merges |
| Option C (single init at hw_params only) | Optional follow-up — may simplify patch |

---

## Open (non-blocking)

| Item | Owner |
|------|-------|
| Submit patch to `alsa-devel` / TI maintainer | Upstream |
| Explain *why* first reinit fails functionally (W7 + PDE23 transient) | Research / cover letter |
| Capture lane post-S2 (KPI-K RW vs MMAP) | Separate closure |

---

## References

- [w4-w6-tas2783-double-reinit-20260714.md](experiments/w4-w6-tas2783-double-reinit-20260714.md)
- [w5-w6-results-20260714.md](experiments/w5-w6-results-20260714.md)
- [w8-context-reinit-protocol.md](experiments/w8-context-reinit-protocol.md)
- [scripts/build-upstream-post-sleep-reinit.sh](../scripts/build-upstream-post-sleep-reinit.sh)
- [scripts/reset-kernel-tree.sh](../scripts/reset-kernel-tree.sh)
