# Installation — ProArt PX13

English · **~15 min** after firmware is installed.

**Hardware:** ASUS ProArt PX13 HN7306EAC · kernel **7.0+**  
**Prerequisites:** [docs/PREREQUISITES.md](docs/PREREQUISITES.md)

---

## 1. Userspace (once)

Use [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix):

- Extract TAS2783 firmware blobs into that repo
- Run `./fix-px13-audio.sh`
- **Reboot**

Disable the brainchillz resume PCI reset if you will use this repo’s kernel stack:

```bash
sudo systemctl disable --now px13-audio-resume.service
```

---

## 2. Kernel source tree (once per machine)

```bash
git clone <this-repo> snd_repair && cd snd_repair
./scripts/prepare-kernel-tree.sh    # needs linux-source package; see PREREQUISITES
```

---

## 3. Apply patches and build (each new kernel)

```bash
sudo ./scripts/apply-upstream-patches.sh      # stereo, FW retry, system-sleep reload
sudo ./scripts/build-from-upstream.sh         # tas2783 + sdw_utils modules

sudo ./scripts/build-upstream-post-sleep-reinit.sh   # fix silent speakers after S2
sudo ./scripts/build-amd-soundwire-resume.sh         # SoundWire attach after S2

sudo ./scripts/install-ucm-px13.sh            # internal mic in GNOME (once)
sudo reboot
```

After a **kernel upgrade**, repeat section 3 only (not firmware/UCM).

---

## 4. Validate

**Cold boot:**

```bash
wpctl status | head -20
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**After suspend:**

```bash
systemctl suspend
# wake, wait ~10 s
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

Pass = **audible tone** on both channels. See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) if not.

Direct ALSA check (stop PipeWire first if `EBUSY`):

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 3
systemctl --user start pipewire pipewire-pulse wireplumber
```

---

## Patch details

See [PATCHES.md](PATCHES.md) and [maintainer/DESIGN.md](maintainer/DESIGN.md).
