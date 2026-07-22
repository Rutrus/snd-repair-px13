# Installation

**Hardware:** ASUS ProArt PX13 HN7306EAC  
**Kernel:** 7.0+ (tested `7.0.0-27-generic`)

Modules install to an **overlay** (`/lib/modules/$(uname -r)/updates/snd_repair/`). Stock in-tree `.ko` files stay untouched. Rollback = remove overlay + reboot.

CLI: [`scripts/snd-repair`](scripts/snd-repair) (`status` | `gate` | `build` | `install-modules` | `rollback`).

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

**Never** run live PCI unbind/bind while the overlay is installed (`PX13_AFTER_SUSPEND=1` / manual `snd_pci_ps` unbind). On 2026-07-19 that froze the machine; safe recover is **cold power cycle** only. See [troubleshooting](docs/troubleshooting.md#post-s2idle-slaves-unattached--fw-timeout-storm).

---

## 4. GRUB escape hatch (once per machine — do this first)

With `GRUB_TIMEOUT=0` / hidden menu you cannot roll back to the previous ABI if a rebuild goes wrong.

```bash
./scripts/snd-repair status          # check TIMEOUT / images
sudo ./scripts/snd-repair gate       # menu ~5s, DEFAULT=saved
# optional harder gate (blacklist auto linux-* upgrades):
# sudo ./scripts/snd-repair gate --full
```

---

## 5. Build + install overlay (each new kernel ABI)

```bash
./scripts/snd-repair status
./scripts/snd-repair build                 # stages modules (no /lib write)
sudo ./scripts/snd-repair install-modules  # → updates/snd_repair + depmod
sudo reboot
./scripts/snd-repair status                # expect 0001 OK / 0002 OK, path under updates/
```

Internal microphone in GNOME (once):

```bash
sudo ./scripts/install-ucm-px13.sh
```

Equivalent manual steps (same overlay):

```bash
./scripts/reset-kernel-tree.sh
./scripts/apply-upstream-patches.sh
./scripts/build-from-upstream.sh
./scripts/build-upstream-post-sleep-reinit.sh    # 0001
./scripts/build-amd-soundwire-resume.sh          # 0002
sudo ./scripts/snd-repair install-modules
```

---

## 6. Verify

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

## Rollback

Overlay only (preferred):

```bash
sudo ./scripts/snd-repair rollback
sudo reboot
```

If an **older** install overwrote in-tree modules (`snd-repair status` shows `legacy in-tree: YES`):

```bash
sudo apt-get install --reinstall linux-modules-$(uname -r)
sudo reboot
```

Or boot the previous kernel from the GRUB menu (gate §4).

---

## After kernel upgrade

Overlay modules are **ABI-specific**. A new `linux-image-*` without rebuild boots **stock** SoundWire drivers.

1. Keep the previous ABI installed until smoke passes.
2. Install headers/source for the new ABI.
3. Boot the new ABI (or build against it), then:

```bash
./scripts/snd-repair build
sudo ./scripts/snd-repair install-modules
sudo reboot
./scripts/snd-repair status
```

4. Smoke (~5 min), then pin GRUB default only if OK:

```bash
sudo grub-set-default 0   # or the entry you validated
```

Do **not** purge the previous `linux-image-*` until the new ABI is validated for ≥1–2 days.

---

## Patch reference

[PATCHES.md](PATCHES.md)
