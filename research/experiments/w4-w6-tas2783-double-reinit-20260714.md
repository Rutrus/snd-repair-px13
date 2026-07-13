# TAS2783 post-S2 silent playback — W4 through W6 (2026-07-13/14)

English (canonical). **Investigation milestone:** same `tas2783_fw_reinit()` works when invoked later; W2 timing is the suspect, not init sequence content.

**Machine:** ProArt PX13 · kernel `7.0.0-27-generic`  
**Stack:** upstream A+B+C + W1 + W2 · `px13-audio-resume.service` **disabled**

---

## Symptom (unchanged)

Post-S2: jack/RT721 OK, PCM2 `RUNNING`, `hw_ptr` advances, mixers sane, W2 `force_fw_reinit ret=0` — **speakers silent**.

---

## Experiment timeline

| ID | Question | Outcome |
|----|----------|---------|
| **W4** | Same lifecycle + SDCA readback cold vs post-S2? | **Identical** — not reg/mute drift |
| **W4b** | Same chip writes during playback window? | Diff tool empty (capture bug); W5 supersedes write-diff |
| **W5** | Does a **second** `fw_reinit()` restore audio? | **YES** — user confirmed audible after manual debugfs reinit |
| **W6** | Is delay or stream event the fix? | **Open** — configurable `delayed_work` sweep |

---

## W5 — key result

```text
Resume → W2 fw_reinit() → silent
(no reboot)
Manual W5 fw_reinit() → audible
```

Same function, same init path. Eliminates:

- Corrupt firmware blob
- Wrong init_seq permanently
- PipeWire / ALSA routing
- SoundWire enum / PCM data path
- Simple FU_MUTE / DAPM POST_PMU absence

**Open:** why the first reinit fails and the second succeeds (timing vs intermediate event vs ordering).

Evidence: `validation/w5-double-reinit-20260714-004420/` (local snapshot; regenerable).

---

## W6 — next experiment (not production fix)

Configurable second reinit after W2:

| Param | Role |
|-------|------|
| `deferred_reinit_ms` | Timer sweep: 0, 500, 1000, 1500, 3000 ms |
| `deferred_reinit_on_port_prep` | Event-driven: first stream `port_prep` after W2 |

Build: `sudo ./scripts/build-w6-deferred-reinit.sh`  
Protocol: [w6-deferred-reinit-protocol.md](w6-deferred-reinit-protocol.md)

**Upstream narrative goal:** show minimum delay threshold (if any), then replace timer with deterministic trigger (SDW attach complete, first `hw_params` / port prep).

---

## Tooling index

| Script | Purpose |
|--------|---------|
| `build-w4-trace.sh` | W4 lifecycle trace |
| `build-w4b-write-trace.sh` | W4 + W4b writes + W5 debugfs |
| `build-w6-deferred-reinit.sh` | W6 deferred second reinit |
| `w4-trace-capture.sh` / `w4-trace-diff.sh` | W4 PASS vs FAIL logs |
| `w4b-write-trace-capture.sh` / `w4-write-trace-diff.sh` | W4b write sequences |
| `w5-double-fw-reinit-test.sh` | Manual second reinit |
| `w6-deferred-reinit-sweep.sh` | One delay value per S2 cycle |
| `tas2783-state-snapshot.sh` | amixer/wpctl/proc snapshot |

Patches: `research/make-it-work/patches/w4-tas2783-trace.patch` (+ apply scripts for W4b/W6).

---

## Hypotheses still open

1. **Timing** — W2 runs before bus/clock stable after resume storm.
2. **Intermediate event** — runtime PM, PLL lock, amp power, final SDW attach between W2 and W5.
3. **Ordering** — W2 before DAPM/clock preconditions required for init_seq to stick.

W6 phase 1 (delay curve) distinguishes (1) from (2)/(3). W6 phase 2 (port_prep) tests event sync.

---

## References

- [post-s2-silent-playback-recovery-20260712.md](post-s2-silent-playback-recovery-20260712.md)
- [silent-resume-tas2783-runtime-state-20260713.md](silent-resume-tas2783-runtime-state-20260713.md)
- [tas2783-probe-vs-fw-reinit-w4-plan-20260713.md](tas2783-probe-vs-fw-reinit-w4-plan-20260713.md)
- [w4-tas2783-trace-protocol.md](w4-tas2783-trace-protocol.md)
- [w4b-write-trace-protocol.md](w4b-write-trace-protocol.md)
- [w6-deferred-reinit-protocol.md](w6-deferred-reinit-protocol.md)
