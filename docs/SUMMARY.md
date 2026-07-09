# ASUS ProArt PX13 audio — one-page summary

> **English** | [Español](es/RESUMEN.md)

**Machine:** ProArt PX13 (HN7306EAC) · **Date:** July 2026

---

## Starting point

On Linux, **built-in speakers produced no sound**. The initial cause was not the kernel: **proprietary calibration firmware** for the TI TAS2783 amplifiers (`1714-1-8.bin` and `1714-1-B.bin`) was missing — on Windows it ships inside the ASUS installer.

## Stage 1 — Bring hardware online

1. Extract `.bin` files from the official ASUS driver (Wine).  
2. Install them under `/usr/lib/firmware/`.  
3. Run `fix-px13-audio.sh` (see [`01-firmware-installation.md`](01-firmware-installation.md)).

→ Audio **started progressing**; without this, kernel debugging would not have been possible.

## Stage 2 — Three kernel bugs (after firmware)

| Problem | Symptom | Fix |
|---------|---------|-----|
| **A** | Error -22 (capture impossible) | Do not use TAS2783 on capture paths |
| **B** | Occasional -110 on reboot | Retries + wait (under validation) |
| **C** | Left speaker only | Split L/R channel across both amps |

→ **Stereo validated** (left and right tested separately).

## Overall outcome

From **no audio** to: firmware installed, SoundWire OK, no -22, working stereo, patches prepared for the Linux kernel.

## Documentation

[`SOLUTION.md`](SOLUTION.md) · [`expert-report.md`](expert-report.md) · [`../upstream/`](../upstream/README.md) · [`KERNEL-UPDATE.md`](KERNEL-UPDATE.md)
