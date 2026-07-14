# W8 / W6 context experiment results

**Status: CLOSED (2026-07-14)** — see [SOLUTION-CLOSURE-TAS2783-POST-S2-20260714.md](../SOLUTION-CLOSURE-TAS2783-POST-S2-20260714.md).

## Valid results (audio confirmed by ear)

| Mode | delay | Audio | Kernel | Valid |
|------|-------|-------|--------|-------|
| W5 manual | — | PASS | ret=0 both uid | yes |
| W6 timer | 3000 ms | PASS | ret=0 both uid (prior session) | yes |
| W6 timer | 0 ms | FAIL (silent) | W2 only | yes (control) |
| **W8 hw-params** | **0 ms** @ 15:57 | **PASS L+R** | W8 ret=0 both uid; follow-up `-s 1`/`-s 2` after PW stop | **yes** |
| **Upstream candidate** | **0 ms** | **PASS** (S2) | `resume_playback_reinit_pending` + clean reinstall | **yes** |

## Invalid / inconclusive runs (do not use for delay threshold)

| Mode | delay | Audio | Kernel | Why invalid |
|------|-------|-------|--------|-------------|
| W6 timer | 1500 ms @ 15:43 | **none** | uid11 **ret=-11 (EAGAIN)**, uid8 ret=0; `port_prep` before W6; speaker-test **EBUSY** | PCM held by PipeWire; 2nd reinit incomplete on uid11; **does not prove 1500 ms FAIL** |
| W8 hw-params @ 15:44 | 0 ms | **none** | W8 armed only; no `W8 ctx=hw_params`; EBUSY | speaker-test never opened PCM → W8 never fired |
| W8 hw-params @ 15:53 | 0 ms | **none** | **W8 hw_params ret=0 both uid** @ ms≈2811; speaker-test **EBUSY** | PipeWire auto-restarted on resume; **kernel valid, audio invalid** |

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
- Follow-up with PW stopped: **`speaker-test -s 1` and `-s 2` both audible L+R**; session audio restored.

**Conclude:** 2nd `fw_reinit()` on first `hw_params` after W2 restores **stereo** with **no timer delay**.

### Interpretation of EAGAIN (-11)

`ret=-11` on uid11 deferred reinit means **EAGAIN** — "cannot complete now", not corrupt FW. Consistent with **device readiness race** during resume storm.

---

## Final hypothesis (accepted)

```text
Resume → W2 fw_reinit too early → silent (ret=0)
      → first hw_params → 2nd fw_reinit → audio
```

Preferred upstream hook: **first `hw_params`**, not `delayed_work`.

---

## Upstream recommendation (implemented)

Patch: [../upstream/patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch](../upstream/patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch)

Build: `sudo ./scripts/build-upstream-post-sleep-reinit.sh`

One-shot `resume_playback_reinit_pending` per system sleep cycle — validated post-S2.

---

## Parked (no further PX13 experiments unless upstream rejects hook)

- W8 port-prep / dapm-pmu modes
- W6 1500 ms threshold sweep
- Option C: skip resume-path reinit, single init at hw_params only
