# Validation

Checklist for **ASUS ProArt PX13 HN7306EAC** with this install stack.  
Re-run after kernel rebuild or major system changes.

---

## Results matrix

| Test | Expected | PX13 (Jul 2026) |
|------|----------|-----------------|
| Cold boot — speakers L+R | Audible stereo | ✔ |
| Cold boot — internal mic | GNOME + `pw-record` | ✔ |
| Cold boot — headphone jack | Playback + headset mic | ✔ |
| Suspend (S2) — speakers | Audible after wake (~10 s) | ✔ |
| Suspend (S2) — internal mic | Works in GNOME | ✔ |
| Suspend (S2) — headset | Works | ✔ |
| Suspend (S2) × 3 | All cycles pass | ✔ |
| PipeWire sink | Speaker (not Dummy Output) | ✔ |
| GNOME Settings → Sound | Speaker + mic visible | ✔ |
| Second playback same boot | No hang / no silence | ✔ |

---

## Quick commands

**Cold boot**

```bash
journalctl -k -b 0 | grep -i tas2783 | grep -iE 'fail|error'   # should be empty
wpctl status
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
pw-record --rate 48000 --channels 1 /tmp/mic-test.wav   # 3 s, Ctrl+C
```

**After suspend**

```bash
systemctl suspend
sleep 10
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**Stereo routing (ALSA)**

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -s 1 -l 3   # left
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -s 2 -l 3   # right
systemctl --user start pipewire pipewire-pulse wireplumber
```

**Modules installed**

```bash
# 0001
zstdcat /lib/modules/$(uname -r)/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst | \
  strings | grep -F 'post-sleep playback fw_reinit failed' && echo "0001 OK"

# 0002
zstdcat /lib/modules/$(uname -r)/kernel/drivers/soundwire/soundwire-amd.ko.zst | \
  strings | grep -F 'amd_sdw_kick_irq_if_pending' && echo "0002 OK"
```

If build failed with `0002 marker not found`, the module in `/lib/modules` was **not** updated — see [troubleshooting](docs/troubleshooting.md#patch-0002-not-installed).

---

## Verified capabilities

- Cold boot playback (stereo)
- Suspend/resume playback (s2idle)
- Internal microphone (PipeWire / GNOME)
- Headset microphone
- Headphone playback
- PipeWire and GNOME audio UI

---

## Known limitations

| Limitation | Impact |
|------------|--------|
| ALSA RW capture after S2 | `arecord -D hw:…` may fail (EIO); use PipeWire / MMAP apps |
| SmartAmp PIN4 capture | Kernel log noise only; not the internal mic |
| Hibernate / hybrid-sleep | Not tested |
| Proprietary firmware | Not in this repo — from brainchillz / ASUS installer |
| Per-kernel rebuild | Modules must be rebuilt after `apt` kernel upgrade |

---

## Full certification protocol

Optional re-test from a clean clone of `main`. Complete lab notebook: branch **`resolution/bruteforce`**.
