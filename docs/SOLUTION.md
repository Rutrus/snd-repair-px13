# How we fixed audio on the ASUS ProArt PX13

> **English** | [Español](es/SOLUCION.md)

**Machine:** ASUS ProArt PX13 (HN7306EAC)  
**Date:** 9 July 2026  
**Audience:** general readers

---

## In one sentence

The laptop went from **no audio at all** to **working stereo** in two stages: install missing proprietary firmware first; then fix **three separate** Linux kernel bugs that only became visible once the hardware could start.

---

## Two project stages

### Stage 1 — Make hardware start

**Initial situation:** after installing Linux, **built-in speakers did not work**. This was not yet an ALSA, SoundWire, or stereo-routing issue — the system **lacked the calibration binaries** Texas Instruments and ASUS use on Windows.

```
Proprietary firmware missing (1714-1-8.bin / 1714-1-B.bin)
        ↓
TAS2783 amplifiers cannot initialize
        ↓
No audio
```

**What we did:**

1. Extract official files from the ASUS installer (SmartAmp TI) using Wine.
2. Copy them to `/usr/lib/firmware/` (`1714-1-8.bin` → left, `1714-1-B.bin` → right).
3. Apply the repair repo (`fix-px13-audio.sh` and [`01-firmware-installation.md`](01-firmware-installation.md)).

**Result:** hardware **started responding**. For the first time the kernel could load firmware, enumerate both amplifiers, and advance the audio chain.

Without this stage, kernel investigation **would not have been possible** — the system failed much earlier.

---

### Stage 2 — Kernel debugging (ALSA / SoundWire)

With firmware in place, **specific** errors appeared that were previously hidden: `-22`, `-110`, left channel only… Instrumentation, hypotheses, and patches followed.

**Method:** reproduce → add traces → rule out causes with evidence → one fix at a time.

```
Problem A — Capture → -22          → patch 0004
Problem B — Firmware → -110        → patches 0006 + 0007 (experimental)
Problem C — Left only              → patch 0009 (L/R split)
```

---

## Full timeline

| Phase | Status |
|-------|--------|
| **0. Stock system** | No audio. Kernel could not find TAS2783 proprietary firmware. |
| **1. ASUS firmware extraction** | `1714-1-8.bin` and `1714-1-B.bin` from official installer → `/usr/lib/firmware/`. |
| **2. Repair repository** | `fix-px13-audio.sh` — hardware can initialize. |
| **3. Kernel investigation** | Specific errors appear; SoundWire/ASoC debugging. |
| **4. Problem A** | Invalid capture on playback-only amp → patch 0004. |
| **5. Problem B** | Intermittent firmware download (`-110`) → 0006 + 0007. |
| **6. Problem C** | Both speakers received the same channel → 0009 → **stereo OK**. |

---

## The three kernel problems (summary)

### A — Impossible capture path

TAS2783 amps on this machine **only play back**; they have no hardware capture port. The system design included them on a “capture” link → error **-22**.

**Fix:** do not connect them to capture streams when hardware does not support it.

---

### B — Second amplifier firmware, sometimes

After reboot, the right speaker failed ~50% of the time loading firmware (**-110**).

**Experimental fix:** retries and wait before playback. Validated with a reboot matrix.

---

### C — Channel routing (only left was heard)

Both amplifiers **did participate**, but both received **both channels at once**. Correct behavior: one channel per speaker.

**Fix:** left channel → left amp, right channel → right amp. **Validated** with separate L/R tests.

---

## Before and after

| Before | After |
|--------|-------|
| No proprietary firmware | ASUS binaries installed and recognized |
| No audio | SoundWire transport and enumeration OK |
| — | Removed `Program transport params failed: -22` (Problem A) |
| — | Mitigated `-110` in tests (Problem B) |
| — | **Stereo left/right** (Problem C) |
| — | Patches documented for kernel maintainers |

---

## Ruled out

- Broken right speaker (works with correct routing).
- Incorrect ACPI enumeration.
- “Second amp does not get play” (it did; wrong channel).
- Blaming only PipeWire or the AMD bus (failure in ASoC / channel split layer).

---

## Main lesson

1. **First**, hardware needs what the vendor does not ship on Linux (proprietary firmware).  
2. **Then**, independent kernel stack bugs can be found and fixed.

Treating “no sound” as a single root cause would have hidden A, B, and C.

---

## More detail

| Document | Content |
|----------|---------|
| [`01-firmware-installation.md`](01-firmware-installation.md) | ASUS firmware extraction (Stage 1) |
| [`expert-report.md`](expert-report.md) | Technical report (traces, code, hypotheses) |
| [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md) | Maintainer-style review (facts vs hypotheses) |
| [`KERNEL-UPDATE.md`](KERNEL-UPDATE.md) | Repeat after kernel upgrade |
| [`../upstream/`](../upstream/README.md) | Patches for official kernel |
| [`../validation/`](../validation/README.md) | Reboot statistics (Problem B) |

---

*July 2026 — ASUS ProArt PX13 / snd_repair*
