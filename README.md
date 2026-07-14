# PX13 Linux audio fix

Kernel patches and install scripts for **ASUS ProArt PX13 (HN7306EAC)** built-in speakers and **suspend/resume playback** on Ubuntu / Linux Mint with kernel **7.0+**.

**Tested:** kernel `7.0.0-27-generic` · July 2026.

---

## What this fixes

| Symptom | Fix |
|---------|-----|
| No stereo / capture `-22` on cold boot | Upstream driver patches (series A+B+C) |
| **Speakers silent after suspend** (PCM runs, no sound) | Post-sleep `hw_params` firmware reinit patch |
| SoundWire codecs not attaching after S2 | AMD SoundWire resume patch |
| Internal mic missing in GNOME | UCM install script |

---

## Quick start (~15 minutes)

1. Install [brainchillz firmware + base UCM](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) and **reboot**.
2. Follow **[INSTALL.md](INSTALL.md)** — kernel tree, patches, rebuild, reboot.
3. Validate after suspend (see INSTALL).

**Do not enable** `px13-audio-resume.service` together with these kernel patches — it causes Dummy Output.

---

## Repository layout

```text
README.md              ← you are here
INSTALL.md             ← step-by-step install
PATCHES.md             ← what each patch does
docs/ARCHITECTURE.md   ← how the stack fits together
docs/TROUBLESHOOTING.md
maintainer/            ← short notes for kernel maintainers
patches/               ← post-sleep playback patch (+ upstream/ series)
scripts/               ← build/install only
```

---

## Full investigation history

All experiments, W-series lab notes, and reproducibility scripts live on branch **`resolution/bruteforce`** — not on `main`.

Maintainers: start with [maintainer/ROOT_CAUSE.md](maintainer/ROOT_CAUSE.md), then switch branch if you need the full lab notebook.

---

## License

Documentation and scripts: [MIT](LICENSE). Kernel patches: **GPL-2.0-only** (same as Linux).
