# Architecture

ASUS ProArt PX13 (HN7306EAC) audio stack — functional view.

---

## Stack diagram

```text
┌─────────────────────────────────────────────────────────┐
│  GNOME / PipeWire / WirePlumber                         │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  ALSA (card: RT721 jack + TAS2783 SmartAmp playback)    │
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

## What each layer needs

### Firmware + UCM (userspace)

- Proprietary TAS2783 calibration blobs in `/lib/firmware/`
- UCM profiles so PipeWire sees **Speaker** and **Internal Mic**

Without firmware: driver cannot initialize amplifiers.

### Base kernel patches (upstream series A+B+C)

- Valid capture path on speaker-only topology
- Firmware download retry and post-sleep reload
- Stereo: one PCM channel per physical TAS2783 (uid `0x8` left, `0xb` right)

Result: **cold boot stereo** works.

### Patch 0002 — AMD SoundWire resume

After S2, pending interrupt status may not dispatch. Patch kicks the IRQ worker so codecs reach **ATTACHED**.

Without this: enumeration may stall after suspend.

### Patch 0001 — post-sleep playback reinit

After S2, resume-path `fw_reinit()` succeeds but speakers stay silent until the **first playback stream** opens. Patch runs one additional `fw_reinit()` at first `hw_params`.

```text
S2 resume
    → firmware reload (resume path)     → silent but ret=0
    → user opens playback
    → first hw_params
    → second fw_reinit (one-shot)       → audio OK
```

---

## Do not combine

| Combination | Result |
|-------------|--------|
| Kernel patches + `px13-audio-resume.service` | Dummy Output / broken stack |
| Manual PCI reset + patched kernel | Overwrites good driver state |

Use **either** brainchillz PCI resume (stock kernel) **or** this kernel stack — not both.

---

## Research branch

Complete investigation notebook: **`resolution/bruteforce`**.
