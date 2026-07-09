# Rollback — restore stock audio stack

> **English** | [Español](es/REVERSION.md)

---

## Kernel modules (stage 2)

### If backups exist in `$HOME`

During install, `build-from-upstream.sh` saves originals as:

```text
~/snd-soc-tas2783-sdw.ko.zst.orig
~/snd-soc-sdw-utils.ko.zst.orig
```

Restore:

```bash
KVER=$(uname -r)
sudo cp ~/snd-soc-tas2783-sdw.ko.zst.orig \
  /lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst
sudo cp ~/snd-soc-sdw-utils.ko.zst.orig \
  /lib/modules/$KVER/kernel/sound/soc/sdw_utils/snd-soc-sdw-utils.ko.zst
sudo depmod -a
sudo reboot
```

### Without backups

Reinstall the distro kernel image (restores stock modules):

```bash
sudo apt install --reinstall linux-image-$(uname -r) linux-modules-$(uname -r)
sudo reboot
```

### Clean patched source tree

```bash
rm -f build/linux-source/.snd-repair-upstream-applied \
      build/linux-source/.snd-repair-upstream-kernel-version \
      build/linux-source/.snd-repair-production-applied \
      build/linux-source/.snd-repair-production-kernel-version
# if tree is git-based:
cd build/linux-source && git checkout -- sound/ 2>/dev/null || true
```

---

## Userspace fix (stage 1 — brainchillz)

The `fix-px13-audio.sh` script installs system files. To remove manually:

```bash
# Firmware (optional — safe to keep)
sudo rm -f /lib/firmware/1714-1-8.bin /lib/firmware/1714-1-B.bin
sudo rm -rf /lib/firmware/ti/audio/tas2783/

# UCM overrides (restore from package on reinstall)
sudo rm -f /usr/share/alsa/ucm2/sof-soundwire/tas2783.conf
# rt721.conf: restore from alsa-ucm-conf package if you replaced it

# Systemd services
sudo systemctl disable --now px13-audio-rebind.service px13-audio-resume.service
sudo rm -f /etc/systemd/system/px13-audio-{rebind,resume}.service
sudo rm -f /usr/local/sbin/px13-audio-fix.sh
sudo systemctl daemon-reload
```

Reinstall ALSA UCM configs:

```bash
sudo apt install --reinstall alsa-ucm-conf
```

---

## Investigation modules (debug path only)

If you installed instrumented `soundwire-amd` / `soundwire-bus` from `patches/0001–0002`:

```bash
KVER=$(uname -r)
sudo cp ~/soundwire-amd.ko.zst.orig \
  /lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst
sudo cp ~/soundwire-bus.ko.zst.orig \
  /lib/modules/$KVER/kernel/drivers/soundwire/soundwire-bus.ko.zst
sudo depmod -a && sudo reboot
```

See [`../patches/README.md`](../patches/README.md).

---

## Verify rollback

```bash
modinfo snd_soc_tas2783_sdw | grep vermagic
journalctl -k -b 0 | grep -i tas2783
wpctl status
```

Expect stock kernel behaviour (original bugs may return without patches).
