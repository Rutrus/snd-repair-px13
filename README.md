# snd_repair — ASUS ProArt PX13 audio on Linux

Documented fix for built-in **TAS2783** (SoundWire) speakers and **resume audio** on the **ASUS ProArt PX13 (HN7306EAC)** under Ubuntu / Linux Mint with kernel 7.0+.

**Result (July 2026):** from no audio to **working stereo on cold boot**. Post-S2 desktop audio: **W1+W2 + brainchillz resume service** — see [silent playback incident](research/experiments/post-s2-silent-playback-recovery-20260712.md) (Jul 12 evening).

> [Español](README.es.md) · License: [MIT](LICENSE) (docs/scripts); kernel patches [GPL-2.0-only](LICENSE)

---

## Practical solution (daily use)

This is the **validated user stack** (KPI-U). Follow it if you want a PX13 that survives **sleep/wake** like a normal laptop.

### When should I apply this?

| Situation | Apply? |
|-----------|--------|
| **No built-in speakers** after installing Linux | **Yes** — start with stage 1 (firmware) |
| Speakers work on **cold boot** but **die after suspend** | **Yes** — you need W1+W2 + UCM mic (below) |
| Only **left speaker** or capture `-22` in dmesg | **Yes** — stage 2 base patches (`build-from-upstream.sh`) |
| **Speaker visible but no sound after S2** | **Yes** — silent playback; keep `px13-audio-resume` enabled; verify **by ear** |
| **Internal mic missing** in Settings but playback OK | **Yes** — run `install-ucm-px13.sh` |
| `arecord -D hw:…` fails with EIO but **GNOME mic works** | **No extra fix needed** — known upstream RW vs MMAP quirk; desktop is fine |
| Different laptop model | **No** — PX13 HN7306EAC only unless you port the patches |

**Tested:** kernel `7.0.0-27-generic` · Ubuntu 26.04 / Linux Mint 22.x.

### Install order (once)

**Prerequisites:** [`docs/PREREQUISITES.md`](docs/PREREQUISITES.md) · full walkthrough: [`docs/INSTALL.md`](docs/INSTALL.md)

```text
Stage 1 — brainchillz (firmware + base UCM + systemd)
Stage 2 — kernel base patches (cold boot: stereo, -22, FW)
Stage 3 — W1 + W2 (resume: SoundWire + TAS2783 FW after S2)
Stage 4 — internal mic UCM (GNOME / PipeWire)
Stage 5 — px13-audio-resume DISABLED (required with W1+W2)
```

| Step | Command | One-time? |
|------|---------|-----------|
| **1. Firmware + UCM** | brainchillz [`fix-px13-audio.sh`](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) — see [`docs/INSTALL.md`](docs/INSTALL.md) | **Yes** — survives kernel upgrades |
| **2. Kernel base** | `./scripts/prepare-kernel-tree.sh` → `./scripts/build-from-upstream.sh` → **reboot** | Rebuild after **each new kernel** |
| **3. Resume fix (W1+W2)** | `sudo ./scripts/build-w1-w2.sh` → **reboot** | Rebuild after **each new kernel** |
| **4. Internal mic** | `sudo ./scripts/install-ucm-px13.sh` → user: `systemctl --user restart wireplumber pipewire` | **Yes** |
| **5. Do not mix** | `sudo systemctl disable --now px13-audio-resume.service` | **Yes** |

**Never combine W1+W2 with `px13-audio-resume`.** After resume W2 loads FW; ~13 s later px13 PCI reset breaks `:8` → **Dummy Output** ([incident](research/experiments/post-s2-silent-playback-recovery-20260712.md)).

**Recover Dummy Output:** `sudo systemctl disable --now px13-audio-resume.service` → **reboot**.

**Do not** run manual `px13-audio-fix.sh` without planning a **reboot**.

Closure details: [`research/SOLUTION-CLOSURE-KPI-U-20260712.md`](research/SOLUTION-CLOSURE-KPI-U-20260712.md)

### Verify it works

**After cold boot:**

```bash
wpctl status                                    # real Speaker sink, not Dummy Output
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**After suspend/resume (the important test):**

Wait **~30 s** after wake (**without** px13-audio-resume), then:

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1   # witness also prompts: did you HEAR it?
./scripts/post-s2-user-witness.sh                    # TTY → ear confirm on by default
```

Pass = **audible** playback (you confirm `y`) + working mic. Use `--no-audible-confirm` only for automation (weaker).

### After a kernel upgrade — do I reapply?

**Yes, for kernel modules. No, for firmware and UCM.**

| Component | Survives `apt upgrade`? | Action after new kernel |
|-----------|-------------------------|-------------------------|
| Firmware `.bin` in `/lib/firmware/` | **Yes** | None |
| UCM (`install-ucm-px13.sh`) | **Yes** | None |
| Patched `.ko` modules | **No** — tied to kernel version | Rebuild (below) |
| W1 / W2 resume modules | **No** | Rebuild (below) |

```bash
# After rebooting into the NEW kernel:
./scripts/post-kernel-update.sh    # rebuilds upstream A+B+C
sudo ./scripts/build-w1-w2.sh      # rebuilds resume fix — required for S2 audio
sudo reboot
./scripts/post-s2-user-witness.sh  # optional sanity check
```

If you skip the rebuild, `modinfo snd_soc_tas2783_sdw | grep vermagic` will **not** match `uname -r` and you fall back to the stock driver → stereo / resume issues return.

Details: [`docs/KERNEL-UPDATE.md`](docs/KERNEL-UPDATE.md)

### Is this “final” / upstream?

| Layer | Status |
|-------|--------|
| **Daily desktop use (KPI-U)** | **Partial** — mic/software validated; **audible playback** needs resume service + ear check |
| **Upstream merge** | **Not yet** — patches are local `.ko` builds, not a distro package |
| **W2 resume hack** | Experimental — works on PX13; may be refined before RFC |
| **Direct `arecord` (RW) after S2** | Still fails — PipeWire uses MMAP; not a user regression |

Treat this as **production-ready for your machine** while you maintain rebuilt modules after kernel updates. It is not “install once forever without maintenance.”

### Something still fails?

| Symptom | Action |
|---------|--------|
| Speaker in GNOME but **no sound** | [Silent playback](research/experiments/post-s2-silent-playback-recovery-20260712.md) — enable `px13-audio-resume`, wait 15 s, **reboot** if you ran manual `px13-audio-fix` |
| Dummy Output | W1+W2, firmware, reboot |
| Mic OK, `arecord` EIO | KPI-K RW quirk — ignore if GNOME mic works |

1. **Always verify by ear:** `speaker-test -D pipewire …` — not witness alone.
2. Modules: `modinfo snd_soc_tas2783_sdw | grep vermagic` vs `uname -r`.
3. Firmware: `journalctl -k -b 0 | grep -i tas2783`.
4. **`px13-audio-resume.service` should be enabled** with W1+W2 on PX13.
5. **Do not** run `sudo px13-audio-fix.sh` mid-session without planning a reboot.

Rollback: [`docs/ROLLBACK.md`](docs/ROLLBACK.md) · troubleshooting: [`docs/INSTALL.md`](docs/INSTALL.md#troubleshooting)

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
| **snd_repair (this repo)** | Stage 2+ — kernel driver bugs (A/B/C), **W1+W2 resume fix**, investigation, upstream-ready patches |

**Both are required** for a complete PX13 experience: brainchillz alone does not fix kernel resume bugs; snd_repair alone fails without firmware.

---

## Production path vs investigation patches

### Recommended — `upstream/` (no debug traces)

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh   # series A + B + C
sudo ./scripts/build-w1-w2.sh      # resume (W1 IRQ + W2 FW reinit)
sudo reboot
```

| Series / layer | Problem | Modules |
|----------------|---------|---------|
| A | Capture -22 on playback-only amp | `snd-soc-tas2783-sdw` |
| B | Firmware timeout -110 (experimental) | `snd-soc-tas2783-sdw` |
| C | Stereo L/R channel split | `snd-soc-tas2783-sdw` + `snd-soc-sdw-utils` |
| W1 | SoundWire re-attach after resume | `soundwire-amd` |
| W2 | TAS2783 FW reload after resume | `snd-soc-tas2783-sdw` |

See [`upstream/README.md`](upstream/README.md). Series B should be treated as **RFC** until more reboots are validated.

### Laboratory — `patches/` (includes `ENZODBG` / `ENZOPLAY`)

Use only when reproducing investigation traces:

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
├── research/                 # Investigation + KPI-U closure docs
└── resolution/               # Engineering experiments (paused post-KPI-U)
```

**Not versioned:** `linux-source-*` (~3 GB). Generated locally (see `.gitignore`).

---

## Hardware

- **Machine:** ASUS ProArt PX13 HN7306EAC  
- **Codecs:** Realtek RT721 (jack) + 2× TI TAS2783 @ `0x8` (L) and `0xB` (R)  
- **Tested kernel:** 7.0.0-27-generic  

---

## Documentation

| Doc | Content |
|-----|---------|
| [`docs/INSTALL.md`](docs/INSTALL.md) | Full install (brainchillz + kernel) |
| [`docs/VERIFICATION.md`](docs/VERIFICATION.md) | Post-install checklist |
| [`docs/KERNEL-UPDATE.md`](docs/KERNEL-UPDATE.md) | After `apt upgrade` |
| [`docs/PROJECT-STATE.md`](docs/PROJECT-STATE.md) | Current project status |
| [`research/SOLUTION-CLOSURE-KPI-U-20260712.md`](research/SOLUTION-CLOSURE-KPI-U-20260712.md) | Resume audio sign-off |
| [`docs/README.md`](docs/README.md) | Full index |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes |

Spanish: [`docs/es/INSTALACION.md`](docs/es/INSTALACION.md) · [`docs/es/README.md`](docs/es/README.md)

---

## Firmware legal note

TAS2783 calibration binaries are **proprietary** (ASUS/TI). This repository does not distribute them. Users must obtain them from the official ASUS installer; see [`docs/01-firmware-installation.md`](docs/01-firmware-installation.md).

---

*July 2026 — ASUS ProArt PX13 / snd_repair*
