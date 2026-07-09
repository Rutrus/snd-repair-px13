# snd_repair — ASUS ProArt PX13 audio on Linux

Documented fix for built-in **TAS2783** (SoundWire) speakers on the **ASUS ProArt PX13 (HN7306EAC)** under Ubuntu / Linux Mint with kernel 7.0+.

**Result:** from no audio to **working stereo on cold boot**. The remaining work is **suspend/resume** (UID `:8` / PM `-110`) — see [`docs/PROJECT-STATE.md`](docs/PROJECT-STATE.md).

> [Español](README.es.md) · License: [MIT](LICENSE) (docs/scripts); kernel patches [GPL-2.0-only](LICENSE)

---

## What this repo is / is not

| This repo **is** | This repo **is not** |
|------------------|----------------------|
| Investigation log + reproducible kernel patches for PX13 speakers | A generic fix for all ASUS laptops |
| Clean patch series for upstream (`upstream/`) | Redistribution of ASUS/TI proprietary firmware |
| Scripts to rebuild modules after kernel upgrades | A signed kernel package or DKMS package (yet) |
| Bilingual documentation (EN default, ES in `docs/es/`) | Tested on every kernel version beyond 7.0.0-27-generic |

**Scope:** ASUS ProArt PX13 (HN7306EAC), AMD ACP70, 2× TAS2783 @ SoundWire. Other machines may need adaptation.

---

## Relationship to [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix)

| Project | Focus |
|---------|--------|
| **brainchillz** | Stage 1 — proprietary firmware, ALSA UCM (`tas2783.conf`, `rt721.conf`), systemd boot/resume |
| **snd_repair (this repo)** | Stage 2 — kernel driver bugs (Problems A/B/C), investigation, upstream-ready patches |

**Recommended order for new users:**

1. Run brainchillz `fix-px13-audio.sh` (see [`docs/INSTALL.md`](docs/INSTALL.md))
2. Apply kernel patches: `./scripts/build-from-upstream.sh`
3. Reboot and verify: [`docs/VERIFICATION.md`](docs/VERIFICATION.md)

---

## Quick start

**Full guide:** [`docs/INSTALL.md`](docs/INSTALL.md) (brainchillz firmware + UCM + systemd, then kernel modules).

| Step | What | Where |
|------|------|-------|
| 1 | Userspace fix (firmware, UCM, suspend) | [brainchillz](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) or [`docs/INSTALL.md`](docs/INSTALL.md) |
| 2 | Prepare kernel source tree | `./scripts/prepare-kernel-tree.sh` |
| 3 | **Build clean modules (recommended)** | `./scripts/build-from-upstream.sh` |
| 4 | Reboot and verify | [`docs/VERIFICATION.md`](docs/VERIFICATION.md) |

Executive summary: [`docs/SUMMARY.md`](docs/SUMMARY.md)  
Maintainer-style review: [`docs/TECHNICAL-REVIEW.md`](docs/TECHNICAL-REVIEW.md)

---

## Production path vs investigation patches

### Recommended — `upstream/` (no debug traces)

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh   # applies series A + B + C, builds .ko
sudo reboot
```

| Series | Problem | Modules |
|--------|---------|---------|
| A | Capture -22 on playback-only amp | `snd-soc-tas2783-sdw` |
| B | Firmware timeout -110 (experimental) | `snd-soc-tas2783-sdw` |
| C | Stereo L/R channel split | `snd-soc-tas2783-sdw` + `snd-soc-sdw-utils` |

See [`upstream/README.md`](upstream/README.md). Series B should be treated as **RFC** until more reboots are validated.

### Laboratory — `patches/` (includes `ENZODBG` / `ENZOPLAY`)

`patches/0001–0009` preserve the **investigation timeline**, including debug printk in `0009`. Use only when reproducing traces:

```bash
./scripts/build-production-modules.sh   # not recommended for daily use
```

---

## Repository layout

```
snd_repair/
├── LICENSE                   # MIT + GPL-2.0 note for kernel patches
├── README.md / README.es.md
├── docs/                     # English (default)
│   └── es/                   # Spanish
├── upstream/                 # Clean patch series (use these)
├── patches/                  # Investigation / debug patches
├── scripts/
├── validation/
└── research/
```

**Not versioned:** `linux-source-*` (~3 GB). Generated locally (see `.gitignore`).

---

## Hardware

- **Machine:** ASUS ProArt PX13 HN7306EAC  
- **Codecs:** Realtek RT721 (jack) + 2× TI TAS2783 @ `0x8` (L) and `0xB` (R)  
- **Tested kernel:** 7.0.0-27-generic  

---

## Documentation

- [`docs/INSTALL.md`](docs/INSTALL.md) — **start here**
- [`docs/README.md`](docs/README.md) — full index  
- [`docs/KERNEL-UPDATE.md`](docs/KERNEL-UPDATE.md) — after `apt upgrade`  
- [`CHANGELOG.md`](CHANGELOG.md) — release notes  
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — patches, DCO, issues  

---

## Firmware legal note

TAS2783 calibration binaries are **proprietary** (ASUS/TI). This repository does not distribute them. Users must obtain them from the official ASUS installer; see [`docs/01-firmware-installation.md`](docs/01-firmware-installation.md).

---

*July 2026 — ASUS ProArt PX13 / snd_repair*
