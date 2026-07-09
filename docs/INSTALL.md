# Full installation guide — ASUS ProArt PX13

> **English** | [Español](es/INSTALACION.md)

End-to-end procedure: **userspace stack** (firmware, UCM, PipeWire) + **kernel patches** (this repo).

**Tested:** Ubuntu 26.04 / Linux Mint 22.x, kernel `7.0.0-27-generic`, ProArt PX13 HN7306EAC.

---

## Overview

| Stage | Repository | What it fixes |
|-------|------------|---------------|
| **1a** | [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) | Proprietary TAS2783 firmware + ALSA UCM + suspend/resume |
| **1b** | This repo (`snd_repair`) | Kernel driver bugs (capture -22, FW -110, stereo L/R) |

Stage 1 alone may produce partial or unstable audio. Stage 2 alone fails without firmware. **Use both.**

---

## Prerequisites

Install packages — see [`PREREQUISITES.md`](PREREQUISITES.md).

---

## Stage 1 — brainchillz (firmware + UCM + systemd)

```bash
git clone https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix.git
cd asus-proart-px13-linux-speaker-fix
```

### 1. Extract firmware (once)

Follow `firmware/EXTRACT-FIRMWARE.md` in that repo, or [`01-firmware-installation.md`](01-firmware-installation.md).

You need these files locally (not redistributed in git):

```text
firmware/1714-1-8.bin   (~40 KB)
firmware/1714-1-B.bin   (~40 KB)
```

### 2. Run the userspace installer

```bash
./fix-px13-audio.sh
```

This installs:

| Component | Purpose |
|-----------|---------|
| Firmware → `/lib/firmware/` | TAS2783 calibration load |
| `tas2783.conf` UCM profile | PipeWire sees internal **Speaker** |
| `rt721.conf` patch | Fixes HiFi verb (removes invalid Headphone Switch) |
| `px13-audio-rebind.service` | ACP PCI reset at **boot** |
| `px13-audio-resume.service` | ACP PCI reset after **suspend/resume** |

### 3. Reboot

```bash
sudo reboot
```

### 4. Quick check (stage 1)

```bash
journalctl -k -b 0 | grep -i tas2783    # no "firmware load ... failed"
wpctl status                             # should list "Audio Coprocessor Speaker"
```

If you still see only **Dummy Output**, stage 1 did not complete correctly — do not proceed to stage 2 yet.

---

## Stage 2 — snd_repair (kernel modules)

```bash
cd /path/to/snd_repair
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
sudo reboot
```

This applies clean upstream series **A + B + C** (no `ENZOPLAY` debug traces) and installs:

- `snd-soc-tas2783-sdw.ko`
- `snd-soc-sdw-utils.ko`

**Note:** Series B (firmware `-110` retry) is **experimental** — treat as RFC-quality until more reboots are validated.

---

## Final verification

See [`VERIFICATION.md`](VERIFICATION.md) for the full checklist.

Minimum:

```bash
# Kernel / firmware
journalctl -k -b 0 | grep -i tas2783

# PipeWire sink
wpctl status

# Stereo (after stage 2)
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1   # left only
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2   # right only

# Optional: via PipeWire default device
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

### Suspend test (stage 1 systemd)

```bash
systemctl suspend
# after wake:
wpctl status
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

---

## After kernel upgrades

```bash
./scripts/post-kernel-update.sh
sudo reboot
```

Details: [`KERNEL-UPDATE.md`](KERNEL-UPDATE.md).

---

## Rollback

[`ROLLBACK.md`](ROLLBACK.md)

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|----------------|--------|
| Dummy Output only | Stage 1 incomplete | Re-run `fix-px13-audio.sh`, check UCM |
| `error playback without fw download` | No firmware | Extract/install `.bin` files |
| Left speaker only | Stage 2 missing | `build-from-upstream.sh` + reboot |
| Audio lost after suspend | systemd resume service | Check `px13-audio-resume.service` |
| `-110` on some reboots | FW race (Serie B) | Reboot again; expand validation matrix |
| `modinfo` vermagic mismatch | Wrong kernel modules | `post-kernel-update.sh` |

Open an issue with the [bug report template](../.github/ISSUE_TEMPLATE/bug_report.md).

---

## Further reading

| Doc | Content |
|-----|---------|
| [`SUMMARY.md`](SUMMARY.md) | One-page overview |
| [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md) | Root cause analysis |
| [`expert-report.md`](expert-report.md) | Full investigation log |
