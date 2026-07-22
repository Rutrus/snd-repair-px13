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

**Modules installed** (prefer CLI)

```bash
./scripts/snd-repair status
# expect: overlay PRESENT, 0001 OK, 0002 OK, path under updates/snd_repair/
```

Manual marker check (works for overlay or in-tree):

```bash
# 0001
modinfo -n snd-soc-tas2783-sdw | xargs zstdcat | \
  strings | grep -F 'post-sleep playback fw_reinit failed' && echo "0001 OK"

# 0002
modinfo -n soundwire-amd | xargs zstdcat | \
  strings | grep -F 'amd_sdw_kick_irq_if_pending' && echo "0002 OK"
```

If build failed with `0002 marker not found`, staging was **not** complete — see [troubleshooting](docs/troubleshooting.md#patch-0002-not-installed).

If `install-modules` claims a **missing 0001/0002 marker** but manual `strings | grep` on staging finds it, see [false-negative marker check](docs/troubleshooting.md#install-modules-missing-0001--0002-marker-false-negative) (fixed in current `lib/modules.sh`).

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
| Per-kernel rebuild | Overlay under `updates/snd_repair/` must be rebuilt after `apt` kernel upgrade |
| GRUB without menu | Apply `sudo ./scripts/snd-repair gate` before risky ABI boots |
| **s2idle re-attach (k28)** | Cold boot OK; **after one s2idle** slaves often stay `UNATTACHED` (`-110`) even with 0001+0002. Safe recover: **cold power** only — never live PCI reset. Track: [`research/s2idle-reattach-k28/`](research/s2idle-reattach-k28/README.md) |

---

## Full certification protocol

Optional re-test from a clean clone of `main`. Complete lab notebook: branch **`resolution/bruteforce`**.
