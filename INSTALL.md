# Installation

**Hardware:** ASUS ProArt PX13 HN7306EAC  
**Kernel:** 7.0+ (tested `7.0.0-27-generic`)

---

## Requirements

```bash
sudo apt install \
  build-essential flex bison libssl-dev libelf-dev dwarves bc zstd \
  linux-headers-$(uname -r) \
  linux-source-$(uname -r | cut -d- -f1-2) \
  git alsa-utils
```

Disk: ~4 GB free for kernel source under `build/`.

---

## 1. Firmware (once)

[brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix):

1. Extract `1714-1-8.bin` and `1714-1-B.bin` into `firmware/`
2. `./fix-px13-audio.sh`
3. **Reboot**

---

## 2. Clone and kernel tree (once)

```bash
git clone https://github.com/Rutrus/snd-repair-px13.git
cd snd-repair-px13
./scripts/prepare-kernel-tree.sh
```

---

## 3. Disable conflicting userspace service (once)

```bash
sudo systemctl disable --now px13-audio-resume.service
```

Do **not** combine `px13-audio-resume` with the kernel patches below.

---

## 4. Build kernel modules (each new kernel)

> **PX13 / colosal3:** before installing or booting a new kernel ABI, apply the update-safety gate (GRUB menu escape hatch, block unattended `linux-*`, keep ≥2 images, smoke-test).  
> Checklist: [fix-gate-kernel-updates.md](../rutrus_workspace/utils/reparar/docs/2026-07-17-fix-gate-kernel-updates.md)  
> Script: `~/rutrus_workspace/utils/reparar/scripts/apply-kernel-safety.sh`

Base driver fixes (stereo, firmware retry, system-sleep reload):

```bash
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
```

Post-suspend fixes:

```bash
sudo ./scripts/build-upstream-post-sleep-reinit.sh    # patch 0001 — speaker playback after S2
sudo ./scripts/build-amd-soundwire-resume.sh          # patch 0002 — SoundWire after S2
```

Internal microphone in GNOME (once):

```bash
sudo ./scripts/install-ucm-px13.sh
```

**Reboot** only after the gate smoke checks (GRUB menu available; prefer X11 on first boot of a new ABI).

---

## 5. Verify

```bash
wpctl status | head -20
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1

systemctl suspend
# wake, wait ~10 s
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

See [VALIDATION.md](VALIDATION.md).

Direct ALSA (if `EBUSY`, stop PipeWire first):

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 3
systemctl --user start pipewire pipewire-pulse wireplumber
```

---

## After kernel upgrade

Out-of-tree modules from this project are **ABI-specific**. A new `linux-image-*` without a rebuild leaves stock SoundWire drivers (or stale modules) and can reintroduce cold-boot / s2idle regressions.

### Prevent auto-boot into an unvalidated kernel (once per machine)

On PX13, an automatic HWE/security kernel install + `GRUB_DEFAULT=0` / hidden timeout boots the newest ABI on the next reboot with no escape hatch. Apply once:

```bash
sudo ~/rutrus_workspace/utils/reparar/scripts/apply-kernel-safety.sh
```

That sets GRUB menu (~5 s) + `saved` default, blacklists `linux-*` in unattended-upgrades, and holds HWE meta packages. Full checklist: [fix-gate-kernel-updates.md](../rutrus_workspace/utils/reparar/docs/2026-07-17-fix-gate-kernel-updates.md).

### Rebuild for the new ABI

1. Install the new kernel packages **manually** (or temporarily `apt-mark unhold` the metas).
2. Install matching headers/source, then rebuild **before** rebooting into the new ABI when possible (or boot the new kernel once, rebuild, reboot again).
3. Repeat **section 4** only (not firmware / UCM):

```bash
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo ./scripts/build-amd-soundwire-resume.sh
```

4. Reboot with GRUB menu available; keep the previous kernel installed until smoke passes.
5. Smoke (~5 min), then set GRUB default to the new kernel only if OK:

```bash
uname -r
journalctl -b 0 | rg -i 'TAS2783 FW broken|amd-soundwire card missing|Xwayland|SEGV'
wpctl status | head -40
modinfo snd_soc_tas2783_sdw | grep vermagic
```

Do **not** purge the previous `linux-image-*` until the new ABI is validated for ≥1–2 days.

---

## Patch reference

[PATCHES.md](PATCHES.md)
