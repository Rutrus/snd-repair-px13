# Architecture — PX13 audio stack

English · two pages.

---

## Stack diagram

```text
┌─────────────────────────────────────────────────────────┐
│  GNOME / PipeWire / WirePlumber                         │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  ALSA (card1: RT721 jack + TAS2783 SmartAmp pcm2)       │
└───────────────────────────┬─────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼──────┐   ┌────────▼────────┐  ┌──────▼──────┐
│ RT721 codec  │   │ TAS2783 ×2      │  │ ACP / SOF   │
│ (jack)       │   │ (speakers L/R)  │  │ PCI audio   │
└───────┬──────┘   └────────┬────────┘  └──────┬──────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                ┌───────────▼───────────┐
                │ AMD SoundWire bus     │
                │ (manager + IRQ path)  │
                └───────────────────────┘
```

---

## Functional layers (what each fix does)

### 1. Firmware + UCM (userspace)

- Loads TAS2783 calibration firmware into `/lib/firmware/`
- UCM tells PipeWire which ALSA devices exist (Speaker, Internal Mic)

Without firmware: driver cannot initialize amps.

### 2. Base kernel patches (series A+B+C)

- **Capture:** avoid invalid capture stream on speaker-only DisCo
- **Firmware path:** retry download, wait in hw_params, reload after system sleep
- **Stereo:** map one PCM channel per physical TAS2783 (Left uid `0x8`, Right uid `0xb`)

Result: **cold boot stereo** works.

### 3. AMD SoundWire resume

After S2, the AMD manager sometimes has pending STAT bits but no IRQ delivery. Patch schedules the IRQ worker manually so codecs reach **ATTACHED**.

Without this: TAS2783 may not complete resume enumeration.

### 4. Post-sleep playback recovery (hw_params reinit)

After S2, the first `fw_reinit()` from the resume path completes with `ret=0` but speakers stay **silent**. The same `fw_reinit()` on the **first playback hw_params** restores audio.

```text
S2 resume
    → firmware reload (resume path)     → silent but ret=0
    → user opens playback stream
    → first hw_params
    → second fw_reinit (one-shot flag)  → audio OK
```

This is **context** (stream setup), not a magic sleep timer.

---

## What not to combine

| Combination | Result |
|-------------|--------|
| Kernel patches + `px13-audio-resume.service` | Dummy Output / broken stack |
| Manual PCI reset scripts + patched kernel | Overwrites good driver state |

Use **either** brainchillz PCI resume **or** this kernel stack — not both.

---

## Maintainer / full lab

Branch **`resolution/bruteforce`**: complete experiment log (W-series), scripts, and validation snapshots.
