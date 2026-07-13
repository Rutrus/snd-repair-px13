# Silent post-S2 playback — reframed hypothesis (2026-07-13)

English (canonical). Supersedes narrow “FU_MUTE / DAPM only” framing for next experiments.

Prior witness: `validation/post-s2-user-witness/20260713-095125` (clean W1+W2 reinstall).

---

## Demonstrated state matrix

| State | Cold boot | After S2 resume |
|-------|-----------|-----------------|
| Speakers audible | **Yes** | **No** |
| Mics (PW) | OK | OK |
| W1 / SoundWire | OK | OK |
| W2 / `fw_ok=1` | OK | OK |
| PipeWire sink | Speaker | Speaker (not Dummy) |
| pcm2p | RUNNING | RUNNING |
| hw_ptr | advances | advances (Δ≈97k in witness) |
| Mixer / Spk switches | ON | ON |
| FU_MUTE POST_PMU (W3 Exp A) | — | fires, writes 0 |

**Conclusion:** Problem is not infrastructure (SDW, ALSA, PW, FW download). It is **localized below PCM/DMA** — TAS2783 internal runtime / analog path after partial `fw_reinit`.

---

## Ruled out (cumulative)

| Layer | Evidence |
|-------|----------|
| W1 IRQ/attach | PHASE7 manual_irq_schedule post-S2 |
| W2 FW ladder | `force_fw_reinit`, no `without fw download` |
| PipeWire | Sink + stream |
| ALSA PCM | RUNNING + hw_ptr |
| User mixer | Spk ON, volumes max |
| Simple FU_MUTE skip | POST_PMU + FU_MUTE=0 (W3 Exp A) |

---

## Cold vs S2 init path (key asymmetry)

**Cold boot:**

```text
probe → FW download → full ASoC/DAPM bring-up → playback → audible
```

**After S2 (W2):**

```text
device never unbinds → fw_reinit() → tas_io_init() only → playback → silent
```

`tas2783_fw_reinit()` does **not** replay full probe/DAPM/power-on sequence. Only invalidates FW flags and reloads firmware.

---

## Primary hypothesis (current)

Not “DAPM forgot FU_MUTE” alone.

**Partial FW reload leaves DSP/analog runtime registers in a default or stale state** while the digital audio path (PCM, DMA, SDW) remains functional.

Plausible missing pieces after `fw_reinit`:

- DSP runtime configuration (outside FW blob)
- Internal routing / class-D / boost / PDE power domains
- Vendor registers not restored by `tas_io_init`
- Calibration-dependent analog path

This explains **PCM RUNNING + hw_ptr + total silence** better than mixer/DAPM-only theories.

---

## Experiment priority (new order)

### E1 — Jack vs speaker discrimination

**Run `20260713-103756` — DISCRIMINATES (jack OK, speakers silent post-S2)**

| Path | Sink / PCM | Heard post-S2 |
|------|------------|---------------|
| Internal speakers | PW sink 62 (Speaker) | **no** |
| Headphones (jack) | PW sink 63 (Headphones) | **yes** |
| rt721 direct | plughw:1,0 | **yes** |
| SmartAmp direct | plughw:1,2 | not tested (EBUSY — PW holds pcm2p) |

Jack detect: `Headphone Jack=on`, `Headphone Switch=on`.

**Conclusion:** Failure is **localized to TAS2783 SmartAmp / analog speaker path**, not shared ASOC/PipeWire upstream. rt721 playback path survives S2; TAS2783 speaker output does not.

Optional confirm (PW stopped):

```bash
systemctl --user stop pipewire wireplumber
speaker-test -D plughw:1,2 -c 2 -t sine -f 440 -l 1
systemctl --user start pipewire wireplumber
```

Expected: silent on hw:1,2 (confirms bypassing PW).

| Headphones | Speakers | Interpretation |
|------------|----------|----------------|
| Audible | Silent | TAS2783 SmartAmp / analog path (localized) |
| Silent | Silent | Shared upstream path (ASoC/routing) |
| Audible | Audible | Intermittent / timing — retest |

### E2 — Codec state diff (cold PASS vs S2 FAIL)

Capture full control surface, not only DAPM:

```bash
# cold boot, after audible confirm:
./scripts/tas2783-state-snapshot.sh --label pass-cold

# after S2, silent, before any PW restart:
./scripts/tas2783-state-snapshot.sh --label fail-silent-s2

diff -ru validation/tas2783-state-pass-cold-* validation/tas2783-state-fail-silent-s2-*
```

Compare: `amixer contents`, DAPM debugfs, jack detect, per-codec mixer values.

### E3 — W3 Experiment B (secondary)

`snd_soc_dapm_sync()` after `fw_reinit` — still worth one run, but **deprioritized** vs E1/E2 given Exp A weakened FU_MUTE-only theory.

### E4 — Targeted W4 (if E2 finds deltas)

Restore **specific registers/controls** identified in E2 diff after `fw_reinit`, not generic `dapm_sync`.

---

## What to stop spending time on

- More W1/W2 variants without new evidence
- PipeWire / UCM / mixer toggles (demonstrated OK)
- KPI-U hw_ptr-only PASS without ear confirm (fixed in witness)

---

## References

- [w3-experiment-a-20260712.md](w3-experiment-a-20260712.md)
- [silent-playback-dapm-fu-mute-20260712.md](silent-playback-dapm-fu-mute-20260712.md)
- Witness: `validation/post-s2-user-witness/20260713-095125`
