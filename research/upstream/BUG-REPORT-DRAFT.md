# Bug report draft — TAS2783 post-S2 silent playback

English (canonical). Copy/adapt for `alsa-devel` or codec maintainer.  
**Status:** ready to send with [0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch](patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch)

**Hardware:** ASUS ProArt PX13 (2× TAS2783 SoundWire SmartAmp) · kernel 7.0 + SOF/SDW  
**Closure:** [SOLUTION-CLOSURE-TAS2783-POST-S2-20260714.md](../SOLUTION-CLOSURE-TAS2783-POST-S2-20260714.md)

---

## Subject line (suggested)

```
ASoC: tas2783: fix silent playback after system sleep (repeat fw_reinit at first hw_params)
```

---

## Problem description

After system suspend/resume (S2), internal speakers are silent on some dual-TAS2783 SoundWire platforms despite:

- Successful firmware download and `tas2783_fw_reinit()` returning `0`
- PCM stream RUNNING with advancing `hw_ptr`
- Headphone jack path (RT721) unaffected
- Identical SDCA register readback vs cold boot (no drift in `init_seq` outcome)

The failure is localized to the TAS2783 SmartAmp playback path, not PipeWire or generic ALSA routing.

---

## Key experimental finding

The discriminative experiment was **not** register diffing — it was **when** the same reinit runs:

```text
S2 resume
  → tas2783_fw_reinit() from update_status()  → ret=0, silent
  → (later) same tas2783_fw_reinit() at first hw_params → audible stereo
```

Manual second reinit via debugfs (W5) reproduced this reliably before any automated fix existed.

A fixed `msleep(3000)` also worked (W6) but is a **readiness proxy**, not an acceptable upstream fix. Triggering the second reinit at the **first playback `hw_params`** with **zero artificial delay** also works (W8) and is the preferred hook.

---

## Proposed wording (body)

> After an S2 resume, `tas2783_fw_reinit()` invoked from `update_status()` completes successfully (`ret=0`, firmware loaded, `init_seq`, SDCA and DAPM apparently correct), yet the amplifiers remain silent. Running the same `tas2783_fw_reinit()` during the first `hw_params` after resume systematically restores audio. This suggests the defect is not the content of the reinit but the **context** in which it runs within the resume cycle (before vs after the first real playback stream setup).

**Avoid claiming (not fully proven):** “the first reinit is X ms too early.” Time and stream context overlap; W8 favours **pipeline context** over magic delay.

---

## Proposed fix (summary)

- On system suspend: invalidate FW bookkeeping; clear one-shot flag.
- On resume-path `fw_reinit()`: set `resume_playback_reinit_pending` on success.
- On first `hw_params` after sleep: run one additional `fw_reinit()`; clear flag.
- Subsequent `hw_params`: no extra reinit.

See patch file for implementation.

---

## Test plan (for maintainers)

1. Cold boot stereo playback PASS  
2. S2 → first playback PASS (audible, both channels on dual-TAS machines)  
3. S2 × 3  
4. Second stream open same boot — no redundant full reinit  
5. Jack + capture regression  

---

## Investigation references (optional attachment)

- W4: lifecycle readback identical PASS/FAIL  
- W5: manual second reinit restores audio  
- W6: timer 3000 ms PASS, 0 ms control FAIL  
- W7: resume timeline (W2 → port_prep → hw_params)  
- W8: hw_params hook @ 0 ms, stereo ear confirm  

Repository: `snd_repair` branch `resolution/bruteforce`, commits `fc5a94c`–`1353a8a` (2026-07-14).

---

## What we ruled out

| Area | Why excluded |
|------|----------------|
| PipeWire | Direct ALSA + jack OK; `hw_ptr` moves |
| Corrupt / missing FW | `fw_ok=1`, same `init_seq`, later reinit works |
| DAPM / FU_MUTE | W3/W4: POST_PMU, mute=0, readback match |
