# ASUS ProArt PX13 — Linux audio fix

Kernel patches for **built-in speakers**, **suspend/resume**, and **microphone** on the **ASUS ProArt PX13 (HN7306EAC)** · Ubuntu / Linux Mint · kernel **7.0+**.

Tested on `7.0.0-27-generic` (July 2026).

---

## Problem

The ProArt PX13 loses **internal speaker audio** after **s2idle suspend** (and related SoundWire / firmware issues on cold boot). PipeWire may show a Speaker sink while output is silent.

---

## Verified (PX13 HN7306EAC)

| Capability | Status |
|------------|--------|
| Cold boot playback (stereo) | ✔ |
| Suspend/resume playback | ✔ |
| Internal microphone (GNOME / PipeWire) | ✔ |
| Headset microphone | ✔ |
| Headphone playback (jack) | ✔ |
| GNOME audio settings | ✔ |
| PipeWire daily use | ✔ |

## Known limitations

- **ALSA read/write capture** after S2 (`arecord` direct) — fails; PipeWire/MMAP capture works
- **SmartAmp PIN4 capture** — not a user microphone path; kernel may log prepare `-22`
- **Hibernate / hybrid-sleep** — not validated (s2idle only)
- **Kernel module rebuild** required after each kernel upgrade

Full investigation history: branch **`resolution/bruteforce`**.

---

## Install (~15 min)

**Prerequisite:** [brainchillz firmware + UCM](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) — extract `.bin` files, run `./fix-px13-audio.sh`, reboot.

Then follow **[INSTALL.md](INSTALL.md)**.

**Important:** disable `px13-audio-resume.service` when using these kernel patches (see INSTALL).

---

## Verify

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1          # cold boot
systemctl suspend && sleep 10
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1          # after wake
```

See **[VALIDATION.md](VALIDATION.md)** for the full checklist.

---

## Docs

| File | Purpose |
|------|---------|
| [INSTALL.md](INSTALL.md) | Copy-paste commands |
| [VALIDATION.md](VALIDATION.md) | What works / known issues |
| [PATCHES.md](PATCHES.md) | What each patch does |
| [docs/architecture.md](docs/architecture.md) | Hardware stack |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failures |

---

## License

Docs and scripts: [MIT](LICENSE). Kernel patches: **GPL-2.0-only**.
