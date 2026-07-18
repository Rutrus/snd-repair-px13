# Troubleshooting

Short fixes for common PX13 audio issues with this install stack.

---

## Dummy Output

**Cause:** `px13-audio-resume.service` (PCI reset) running together with kernel patches.

**Fix:**

```bash
sudo systemctl disable --now px13-audio-resume.service
sudo reboot
```

---

## No Speaker sink / no internal speakers in Settings

**Cause:** Firmware or UCM not installed.

**Fix:** Run [brainchillz `fix-px13-audio.sh`](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix), reboot.

```bash
ls -l /lib/firmware/1714-1-8.bin /lib/firmware/1714-1-B.bin
journalctl -k -b 0 | grep -i tas2783
```

---

## Speaker visible but silent after suspend

**Cause:** Patch 0001 not loaded, or PipeWire holds stale device.

**Check:**

```bash
zstdcat /lib/modules/$(uname -r)/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst | \
  strings | grep -F 'post-sleep playback fw_reinit failed' || echo "rebuild 0001"
```

**Fix:**

```bash
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo reboot
```

Test with PipeWire stopped (rules out EBUSY):

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
systemctl suspend && sleep 10
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 3
systemctl --user start pipewire pipewire-pulse wireplumber
```

---

## Patch 0002 not installed

**Symptoms:**

- `build-amd-soundwire-resume.sh` exits with `ERROR: 0002 marker not found in .../soundwire-amd.ko`
- Verification prints nothing:

```bash
zstdcat /lib/modules/$(uname -r)/kernel/drivers/soundwire/soundwire-amd.ko.zst | \
  strings | grep amd_sdw_kick_irq_if_pending && echo OK
```

- Installed module still shows lab strings:

```bash
zstdcat /lib/modules/$(uname -r)/kernel/drivers/soundwire/soundwire-amd.ko.zst | \
  strings | grep PHASE7 && echo "lab module — replace"
```

If `build-amd-soundwire-resume.sh` prints `ERROR: 0002 marker not found in .../soundwire-amd.ko`:

- **Cause:** stale `soundwire-amd.o` in the build tree, or `amd_manager.c` still contaminated with phase7 from the lab branch.
- **Not installed:** script exits before copying to `/lib/modules` — old module remains loaded after reboot.

**Fix:**

```bash
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo ./scripts/build-amd-soundwire-resume.sh
sudo reboot
```

After reboot, expect `0002 OK` from [VALIDATION.md](../VALIDATION.md).

---

**Cause:** Series C channel-map patch not applied.

**Fix:**

```bash
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
sudo reboot
```

---

## Internal microphone missing in GNOME

**Fix:**

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

---

## `speaker-test`: Device or resource busy

PipeWire owns the PCM. Stop user services (see above) or use `-D pipewire`.

---

## After kernel upgrade — audio broken

Modules are tied to kernel version. Rebuild:

```bash
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo ./scripts/build-amd-soundwire-resume.sh
sudo reboot
```

Verify:

```bash
modinfo snd_soc_tas2783_sdw | grep vermagic
uname -r
```

---

## `arecord` fails after suspend but GNOME mic works

**Expected limitation.** Direct ALSA read/write capture can fail post-S2; PipeWire uses MMAP and works. Not a regression for desktop use.

---

## Still stuck

Open an issue with: kernel version (`uname -r`), `journalctl -k -b 0 | grep -i tas2783`, cold boot vs post-S2.

Deep investigation: branch **`resolution/bruteforce`**.
