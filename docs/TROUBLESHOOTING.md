# Troubleshooting

English · short.

---

## Dummy Output after resume

**Cause:** `px13-audio-resume.service` (PCI reset) ran while kernel resume patches are active.

**Fix:**

```bash
sudo systemctl disable --now px13-audio-resume.service
sudo reboot
```

---

## Speaker visible but no sound after suspend

**Cause:** Post-sleep playback patch not loaded, or PipeWire holds stale device.

**Check:**

```bash
# Module built with post-sleep fix (string in ko)
strings /lib/modules/$(uname -r)/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst | \
  grep -F 'post-sleep playback fw_reinit failed' && echo OK

# Rebuild if missing:
sudo ./scripts/build-upstream-post-sleep-reinit.sh && sudo reboot
```

**Test with PipeWire stopped** (rules out EBUSY):

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
systemctl suspend && sleep 5
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 3
systemctl --user start pipewire pipewire-pulse wireplumber
```

---

## Only left or right speaker

**Cause:** Series C channel-map patch not applied.

**Fix:** `sudo ./scripts/apply-upstream-patches.sh` and `sudo ./scripts/build-from-upstream.sh`, reboot.

---

## Internal microphone missing in Settings

**Fix:**

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

---

## Firmware load failed in dmesg

**Cause:** brainchillz firmware not installed.

**Fix:** [brainchillz installer](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) — extract `.bin` files first.

---

## `speaker-test`: Device or resource busy

PipeWire owns the PCM. Stop it (see above) or use `-D pipewire`.

---

## Still stuck

Open an issue with: kernel version, `journalctl -k -b 0 | grep -i tas2783`, and whether cold boot vs post-S2.

Full investigation branch: `resolution/bruteforce`.
