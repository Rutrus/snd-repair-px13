# Investigation index — PX13 snd_repair

> **Unified model (canonical):** [`UNIFIED-CAUSAL-MODEL.md`](UNIFIED-CAUSAL-MODEL.md)  
> **Journey:** [`JOURNEY.md`](JOURNEY.md) · **State:** [`../docs/PROJECT-STATE.md`](../docs/PROJECT-STATE.md)  
> **Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`

**One investigation thread** since 2026-07-12. Historical tracks A–D and Phases 5–8 are **layer elimination**, not parallel hypotheses.

**Active line:** [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) — **Q3:** first missing SoundWire re-attach transition (state-based).

---

## Branch map

| Branch | Role | Status | Document |
|--------|------|--------|----------|
| **Q3 SDW re-attach** | First missing state after resume | **ACTIVE P0** | [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md) |
| **Q2 fw trace** | H1–H4 witness | **Closed (cycle)** | [experiments/q2-fw-trace-witness-20260712.md](experiments/q2-fw-trace-witness-20260712.md) |
| **Track PCM2** | Q1 closed | Closed | [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md) |
| Phase 5 | Codec lifecycle ruled in/out | Closed | [phase-5/INDEX.md](phase-5/INDEX.md) |
| Phase 6–8 | IRQ delivery boundary (remote cause **candidate**) | **Frozen** | [frozen/upstream-proof/](frozen/upstream-proof/) |
| **Track A** | FW `:8` — same chain, earlier altitude | Absorbed | [track-A-serie-b-suspend.md](track-A-serie-b-suspend.md) |
| **Track B** | Capture `-22` | Closed | [track-B-capture-pin4.md](track-B-capture-pin4.md) |
| **Track C** | Webcam media0 (independent) | P3 | [tracks/TRACK-C-WEBCAM-MEDIA0.md](tracks/TRACK-C-WEBCAM-MEDIA0.md) |
| **Track D** | PipeWire / px13 (aggravator) | Mitigated | [track-D-userspace-pipewire.md](track-D-userspace-pipewire.md) |
| resolution/lab | S2→S3 recovery edges | Paused | [../resolution/README.md](../resolution/README.md) |
| resolution/bruteforce | Negative: rebuild ≠ fix | Frozen | [../resolution/bruteforce/README.md](../resolution/bruteforce/README.md) |
| resolution/rescue | Negative: levels A–D | Paused | [../resolution/rescue/README.md](../resolution/rescue/README.md) |

---

## Unified causal chain (summary)

```text
Resume → status != ATTACHED (Q3 open: first missing re-attach step)
       → no FW async (Q2 closed) → hw_params -EINVAL (Q1 closed)
       → Dummy Output
```

**Separate evidence from explanation** before upstream mail. Details: [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md).

---

## What is demonstrated vs inferred

| Demonstrated | Inferred / open |
|--------------|-----------------|
| PCM0 PASS · PCM2 EINVAL post-resume | Which step fails re-attach (manager vs core vs machine) |
| Pre-DMA `set_params` failure | IRQ **causes** attach failure (needs same-boot proof) |
| No observable `io_init` before hw_params timeout (Q2) | 0003 fixes when ATTACHED never returns |
| Both `:8` and `:b` resume init timeout | Phase 6–8 **causes** Q2 witness chain |
| Phase 6–8: STAT pending, no handler in FAIL | Serie B alone fixes resume |

---

## Current priority

**Q3:** First missing SoundWire re-attach transition after resume. See [q2.5-sdw-reattach/README.md](q2.5-sdw-reattach/README.md).

Do not assume break at `manager_reset`. Instrument manager/core ladder on one boot.

---

## Collection

```bash
~/snd_repair/scripts/investigation-snapshot.sh
~/snd_repair/scripts/fw-validation-run.sh status
```

---

## Closure criteria

| Branch | Closed when |
|--------|-------------|
| Track PCM2 / project | Q1: rejecting function named; ≥6/6 real suspend/resume OK without reboot |
| Phase 6–8 upstream | Mail sent or maintainer ack (IRQ boundary — separate from Q1) |
| Track B | Already closed (0004) |
| Track C | 0× EACCES on media0 |
| Track D | px13-resume stable; no PW SIGKILL |
