# W8 / W6 context experiment results

## Valid results (audio confirmed by ear)

| Mode | delay | Audio | Kernel | Valid |
|------|-------|-------|--------|-------|
| W5 manual | — | PASS | ret=0 both uid | yes |
| W6 timer | 3000 ms | PASS | ret=0 both uid (prior session) | yes |
| W6 timer | 0 ms | FAIL (silent) | W2 only | yes (control) |
| **W8 hw-params** | **0 ms** @ 15:57 | **PASS L+R** | W8 ret=0 both uid; follow-up `-s 1`/`-s 2` after PW stop | **yes** |

## Invalid / inconclusive runs (do not use for delay threshold)

| Mode | delay | Audio | Kernel | Why invalid |
|------|-------|-------|--------|-------------|
| W6 timer | 1500 ms @ 15:43 | **none** | uid11 **ret=-11 (EAGAIN)**, uid8 ret=0; `port_prep` before W6; speaker-test **EBUSY** | PCM held by PipeWire; 2nd reinit incomplete on uid11; **does not prove 1500 ms FAIL** |
| W8 hw-params @ 15:44 | 0 ms | **none** | W8 armed only; no `W8 ctx=hw_params`; EBUSY | speaker-test never opened PCM → W8 never fired |
| W8 hw-params @ 15:53 | 0 ms | **none** | **W8 hw_params ret=0 both uid** @ ms≈2811; speaker-test **EBUSY** | PipeWire auto-restarted on resume, opened pcm2p before speaker-test; **kernel valid, audio invalid** |

### W8 hw-params @ 15:57 — **VALID PASS** (kernel + audio)

Resume @ 15:57:08:

```text
ms=0–2673    W2 both uid
ms=7884      speaker-test hw_params → W8 uid8 (Left)
ms=10270     W8 uid8 ret=0
ms=12855     W8 uid11 ret=0 (Right)
             playback after both complete
```

- In-script `-l 1` (~59 ms/channel): user reported **Right only** — inconclusive for stereo.
- Follow-up @ ~16:06 with PW stopped: **`speaker-test -s 1` and `-s 2` both audible L+R**; session audio restored.

**Conclude:** 2nd `fw_reinit()` on first `hw_params` after W2 restores **stereo** with **no timer delay** — preferred upstream hook over W6 `delayed_work`.

### W8 hw-params @ 15:53 — kernel PASS (audio not tested)

Resume @ 15:53:39 (W7 anchor ms=0):

```text
ms=0–1338   W2 uid11
ms=1339–2674 W2 uid8
ms=2789     first_port_prep  ← PipeWire pid 5773 (resume autostart)
ms=2811     first_hw_params + W8 fw_reinit uid8 start
ms=5274     W8 uid8 ret=0
ms=7759     W8 uid11 ret=0
```

**Conclude:** 2nd `fw_reinit()` on first `hw_params` after W2 succeeds with **~0 ms artificial delay** — pipeline milestone, not timer sleep.  
**Do not conclude audio PASS** until a clean run with PipeWire masked through speaker-test.

### Interpretation of EAGAIN (-11)

`ret=-11` on uid11 deferred reinit means the driver returned **EAGAIN** — "cannot complete now", not "firmware/init_seq permanently wrong". Consistent with **device readiness race** during resume storm, not with corrupt FW.

### W7 timeline — last valid timer run (15:43:48, invalid audio)

```text
ms=0       s2_resume_anchor
ms=1–1337  W2 uid11 (~1.3 s)
ms=1338–2672 W2 uid8 (~1.3 s)   ← full W2 sequence for both TAS ~2.7 s (sequential; not proven "blocking")
ms=2794    first_port_prep (PipeWire — contaminates test)
ms=2893+   W6 2nd reinit uid11 → ret=-11
ms=7729    W6 2nd reinit uid8  → ret=0
```

**Do not conclude:** "1500 ms is insufficient."  
**Do conclude:** "1500 ms run with PW active + parallel per-uid timers produced incomplete 2nd reinit."

---

## Working hypothesis (2026-07-14)

```text
Resume
  → ACP / SoundWire / TAS2783 wake
  → W2 fw_reinit too early (device not ready)
  → returns OK but DSP path not audibly operational

Later (after readiness — time and/or pipeline milestone)
  → 2nd fw_reinit
  → DSP operational
  → audio
```

Time (1500 / 3000 ms) is likely a **symptom** of readiness, not the root cause. Preferred upstream hook: **deterministic readiness event** (first `hw_params`, DAPM POST_PMU, or bus-stable signal) over fixed sleep.

---

## Next experiments (priority)

1. ~~W8 hw-params clean audio~~ — **done** (15:57 + L/R confirm).

2. **W8 port-prep / dapm-pmu** — only if upstream needs earlier hook than `hw_params` (lower priority).

3. **W6 timer 1500 ms** repeat with PW masked — optional contrast; event hook preferred.

4. **Upstream patch draft** — 2nd `fw_reinit()` in `hw_params` when `resume_reinit_pending` after W2 (see recommendation below).

---

## Upstream recommendation

**Confirmed (2026-07-14):** after resume-time W2 `fw_reinit()`, defer a second `fw_reinit()` until the **first `hw_params`** on that PCM path (both uid, sequential). No `delayed_work` sleep. W6 timer remains a fallback workaround (`deferred_reinit_ms=3000`) until patch lands.
