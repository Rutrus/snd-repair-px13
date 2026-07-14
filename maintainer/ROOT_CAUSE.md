# Root cause — post-S2 silent SmartAmp

English · maintainer summary.

---

## Symptom

After system suspend/resume, **internal speakers are silent** on dual-TAS2783 SoundWire laptops (validated: ASUS ProArt PX13) although:

- `tas2783_fw_reinit()` returns **0**
- Firmware reports loaded (`fw_ok=1`), `init_seq` runs
- PCM is **RUNNING**, `hw_ptr` advances
- Headphone path (RT721) works
- SDCA readback matches cold boot (no register drift)

---

## Isolation

| Ruled out | Evidence |
|-----------|----------|
| PipeWire / routing | Direct ALSA + jack OK |
| Corrupt firmware | Same `fw_reinit()` works later |
| Missing DAPM / mute | POST_PMU, FU_MUTE=0, W4 readback identical |

Defect is **TAS2783 playback path after S2**, not userspace.

---

## Root cause class

**Wrong context for firmware reinitialization during the resume cycle.**

`tas2783_fw_reinit()` from `update_status()` after sleep completes successfully but leaves amps **functionally silent**. The **same function** during the **first `hw_params`** after resume restores stereo.

Do **not** over-claim “N milliseconds too early” — time and stream context overlap; event-driven fix at `hw_params` (0 ms delay) discriminates in favour of **pipeline context** (no active PCM stream yet at resume-path reinit).

---

## Bug report wording

> After an S2 resume, `tas2783_fw_reinit()` from `update_status()` completes successfully yet amplifiers remain silent. Running the same `tas2783_fw_reinit()` during the first `hw_params` after resume systematically restores audio. The defect is not reinit content but **when** it runs in the resume cycle.

---

## Full evidence

Branch **`resolution/bruteforce`** — experiments W4–W8, timelines, false hypotheses.

See [EXPERIMENT_SUMMARY.md](EXPERIMENT_SUMMARY.md).
