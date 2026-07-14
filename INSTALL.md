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

**Reboot.**

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

Repeat **section 4** only (not firmware / UCM).

```bash
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo ./scripts/build-amd-soundwire-resume.sh
sudo reboot
```

Check module matches running kernel:

```bash
modinfo snd_soc_tas2783_sdw | grep vermagic
uname -r
```

---

## Patch reference

[PATCHES.md](PATCHES.md)
