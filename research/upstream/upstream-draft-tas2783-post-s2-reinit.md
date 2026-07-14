# Upstream draft — TAS2783 post-S2 silent playback

English (canonical). **Status:** **CLOSED** — upstream candidate validated post-S2 + clean reinstall. See [SOLUTION-CLOSURE-TAS2783-POST-S2-20260714.md](../SOLUTION-CLOSURE-TAS2783-POST-S2-20260714.md).

**Hardware:** ASUS ProArt PX13 (TAS2783 SmartAmp ×2, uid `0x8` Left / `0xb` Right)  
**Kernel:** Linux 7.0 + SOF/SDW stack

---

## Problem

After system suspend/resume, internal speakers are **silent** despite:

- Successful firmware download (`fw_dl_success=1`)
- Identical `init_seq` and SDCA readback vs cold boot (W4)
- PCM2 RUNNING, `hw_ptr` advancing
- PipeWire / RT721 / jack path unaffected

First `tas2783_fw_reinit()` on the resume / `update_status(ATTACHED)` path returns without error but leaves the SmartAmp path **functionally non-audible**.

---

## Hypothesis evolution

| Hypothesis | Status |
|------------|--------|
| Corrupt firmware after S2 | ❌ Same `fw_reinit()` works later |
| Missing `init_seq` writes | ❌ W4 — no relevant diff |
| DAPM / FU_MUTE not running | ❌ W3/W4 |
| PipeWire / ALSA routing | ❌ Jack OK; PCM runs |
| TAS2783 wrong state during resume ordering | ✅ Consistent with all evidence |

**Strongest causal chain (validated):**

```text
Resume
    ↓
W2 force_fw_reinit()          ← too early in resume ordering
    ↓
silent (ret=0, not audible)
    ↓
first real hw_params           ← stream about to play; bus/DAPM/ports ready
    ↓
second fw_reinit()
    ↓
stereo audio
```

This is **event ordering**, not a random race and not a magic millisecond count.

---

## Why `hw_params` is the right hook

`hw_params` runs when playback is actually being configured. By then, typically:

- PCI / ACP resume completed
- SoundWire enumeration and manager programming done
- Runtime PM and regcache sync done
- DAPM path engaged for the stream
- PCM opened (userspace or direct ALSA)
- Clocks and port prep in progress or complete

`update_status(ATTACHED)` during resume occurs **much earlier**, while the subsystem is still reassembling — plausible that `fw_reinit()` there programs the DSP before the analog/stream path is ready to use it.

W7 anchor data (15:57 PASS): W2 ends ~2673 ms; first `hw_params` at ~7884 ms (includes script wake delay). In uncontaminated runs, `first_hw_params` follows `first_port_prep` by tens of ms.

---

## W6 vs W8

| Approach | Meaning |
|----------|---------|
| W6 `deferred_reinit_ms=3000` | “Wait until stable, then reinit” — **time as proxy** |
| W8 `deferred_reinit_on_hw_params` | “Wait until playback milestone, then reinit” — **event-driven** |

W6 @ 1500 ms contaminated run (EAGAIN, PW EBUSY) does **not** prove 1500 ms is insufficient.  
W8 @ 0 ms delay + stereo confirm **does** prove the milestone matters more than sleep.

---

## Upstream patch design

**File:** [patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch](patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch)

### State machine (one-shot per sleep cycle)

```text
system_suspend:
    post_system_sleep = true
    resume_playback_reinit_pending = false
    invalidate hw_init / fw flags

update_status(ATTACHED) or system_resume + post_system_sleep:
    regcache sync
    fw_reinit()                              ← first (resume-phase) init
    resume_playback_reinit_pending = true    ← arm only on success

first hw_params after sleep:
    if resume_playback_reinit_pending:
        fw_reinit()                          ← second (playback-phase) init
        resume_playback_reinit_pending = false

second and later hw_params:
    no extra reinit

UNATTACHED / suspend:
    resume_playback_reinit_pending = false
```

**Critical for upstream acceptance:** second reinit runs **once per system sleep**, not on every stream open.

### Build (local tree)

```bash
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo reboot
```

Applies on top of existing kernel tree via `scripts/apply-upstream-post-sleep-hw-params.py` (replaces W2 debug strings when present).

---

## Validation evidence

| Test | Audio | Kernel | Notes |
|------|-------|--------|-------|
| W5 manual 2nd reinit | PASS | ret=0 | Same function, later |
| W6 timer 3000 ms | PASS | ret=0 both uid | Time proxy |
| W6 timer 0 ms | FAIL | W2 only | Control |
| W8 hw-params @ 15:57 | **PASS L+R** | W8 ret=0 both uid | PW masked; `-s 1`/`-s 2` confirm |
| **Upstream candidate** @ 16:24 | **PASS** | `resume_playback_reinit_pending` | `build-upstream-post-sleep-reinit.sh` on W2–W8 tree |

Full table: [../experiments/w8-context-results.md](../experiments/w8-context-results.md)

### Clean reinstall from commit

`linux-source-*/` is **gitignored** — `git checkout -- …/tas2783-sdw.c` does not apply.

```bash
git checkout resolution/bruteforce   # fc5a94c + 5ebce3b

sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo reboot
```

---

## Test plan for upstream submission

1. Cold boot → stereo playback PASS  
2. S2 → first `speaker-test hw:1,2` → stereo PASS (mask PW if EBUSY)  
3. S2 × 3 repeat  
4. Second `hw_params` on same boot → no extra FW reload (no latency spike / dmesg spam)  
5. Jack, DMIC, capture — no regression  
6. Mutually exclusive with `px13-audio-resume` PCI reset userspace

### One-shot verification

```bash
# After one successful playback post-S2:
journalctl -k -b 0 | grep -c 'post-sleep playback fw_reinit failed'   # expect 0
speaker-test -D hw:1,2 ...   # second open — should not trigger extra full reinit
# (Optional: compare W4 readback / FW download count vs first open)
```

---

## Open question — why first `fw_reinit()` fails functionally

Not required to fix the bug, but strengthens the commit message for maintainers.

**Observed ordering (W7):**

```text
ms=0        s2_resume_anchor
ms=1–1337   W2 uid11 fw_reinit
ms=1338–2673 W2 uid8 fw_reinit
ms=2789     first_port_prep
ms=2811     first_hw_params → W8 reinit → audio
```

**Candidate “not ready yet” during W2:**

| Dependency | Ready at W2? | Ready at hw_params? |
|------------|--------------|---------------------|
| SoundWire ATTACHED | yes | yes |
| SDCA port PRE_PREP / channel mask | often no | yes |
| PDE23 power / FU21 DAPM | partial | yes |
| ACP clock domain for stream | uncertain | yes |
| Both TAS2783 sequential (~2.7 s apart) | uid8 after uid11 | single stream setup |

**Follow-up probes (optional):**

- W7 diff: `w2_fw_reinit_end` → `first_port_prep` vs `first_hw_params` on PASS/FAIL  
- W4 readback at W2 exit vs W8 exit (PDE23 transient `3/0` seen during W8 reinit @ 15:57)  
- **Option C experiment:** skip resume-path `fw_reinit()`, single init at first `hw_params` only — if PASS, simplify patch to one init at correct time

---

## Cover letter summary (for maintainers)

> Post-system-sleep `tas2783_fw_reinit()` on SoundWire ATTACHED completes successfully but leaves speakers silent on some dual-TAS2783 machines. Identical reinit at the first playback `hw_params` restores output. W4 eliminated register/init_seq drift; W5 proved a second reinit fixes it; W6 showed timing was a readiness proxy; W8 confirmed an event-driven hook with zero artificial delay and stereo ear validation. Proposed fix: arm `resume_playback_reinit_pending` after resume-path reinit; perform one additional `fw_reinit()` on the first `hw_params` only.

---

## References

- [w8-context-results.md](../experiments/w8-context-results.md)
- [w8-context-reinit-protocol.md](../experiments/w8-context-reinit-protocol.md)
- [w4-w6-tas2783-double-reinit-20260714.md](../experiments/w4-w6-tas2783-double-reinit-20260714.md)
- [w5-w6-results-20260714.md](../experiments/w5-w6-results-20260714.md)
