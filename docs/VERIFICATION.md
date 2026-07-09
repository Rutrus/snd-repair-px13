# Verification checklist

> **English** | [Español](es/VERIFICACION.md)

Use after **stage 1** (brainchillz) and again after **stage 2** (kernel modules). See [`INSTALL.md`](INSTALL.md).

---

## 1. Firmware loaded

```bash
journalctl -k -b 0 | grep -i tas2783
```

**Pass:** no lines containing:

- `Direct firmware load for 1714-1-8.bin failed`
- `error playback without fw download`
- `FW download failed` (ideal; occasional `-110` may still occur before Serie B)

**Files on disk:**

```bash
ls -lh /lib/firmware/1714-1-8.bin /lib/firmware/1714-1-B.bin
# expect ~40 KB each
```

---

## 2. SoundWire enumeration

```bash
ls /sys/bus/soundwire/devices/
```

**Pass:** three devices visible (RT721 + two TAS2783 slaves `0x8` and `0xb`).

---

## 3. PipeWire / UCM (stage 1)

```bash
wpctl status
```

**Pass:** sink such as **Audio Coprocessor Speaker** (not only Dummy Output).

```bash
alsaucm -c "$(cat /proc/asound/cards | awk '/ProArtPX13/{print $2}')" get _verb
# expect HiFi or similar active profile
```

---

## 4. Kernel modules (stage 2)

```bash
uname -r
modinfo snd_soc_tas2783_sdw | grep -E 'filename|vermagic'
modinfo snd_soc_sdw_utils 2>/dev/null | grep vermagic || \
  modinfo snd_soc_sdw_utils | grep vermagic
```

**Pass:** `vermagic` matches running kernel exactly.

**Pass:** no `ENZOPLAY` strings in production build:

```bash
modinfo -n snd_soc_tas2783_sdw | xargs zstdcat 2>/dev/null | strings | grep ENZOPLAY
# should return nothing when built with build-from-upstream.sh
```

---

## 5. Stereo playback

### ALSA direct (validates kernel routing)

Card/device numbers may vary; PX13 typically uses card 1, device 2:

```bash
aplay -l | grep -i smart
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1   # left channel only
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2   # right channel only
```

**Pass:** audible sound from the expected side only.

### PipeWire (daily use)

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**Pass:** stereo tone from both speakers.

---

## 6. Suspend / resume (stage 1 systemd)

```bash
systemctl is-enabled px13-audio-resume.service
systemctl suspend
# after wake:
wpctl status | grep -i speaker
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**Pass:** speaker sink returns; audio audible without manual intervention.

---

## 7. Capture regression (Serie A)

Playback should work even if capture dailink still logs prepare warnings:

```bash
journalctl -k -b 0 | grep -i 'Program transport params failed'
```

Known residual on PX13: `SDW1-PIN4-CAPTURE-SmartAmp` prepare `-22` — does **not** block speaker playback. See [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md).

---

## Quick pass/fail summary

| Check | Stage |
|-------|-------|
| Firmware in dmesg OK | 1 |
| `wpctl` shows Speaker | 1 |
| Suspend recovery | 1 |
| `vermagic` match | 2 |
| `speaker-test -s 1` / `-s 2` | 2 |
| No persistent `-110` on both UIDs | 2 (best effort) |
