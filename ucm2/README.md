# UCM overrides — ASUS ProArt PX13

English (canonical). Install with [`../scripts/install-ucm-px13.sh`](../scripts/install-ucm-px13.sh).

## Files

| File | Purpose |
|------|---------|
| `sof-soundwire/acp-dmic.conf` | HiFi **Mic** device → `hw:${CardId},4` (internal DMIC) |

Machine card conf patch (append only):

```text
Define.MicCodec1 "acp-dmic"
```

Triggers `HiFi.conf` → `Include.micdev` → `acp-dmic.conf`.

## Prerequisites

- brainchillz stage 1 (`tas2783.conf`, machine conf under `/usr/share/alsa/ucm2/conf.d/amd-soundwire/`)
- `arecord -D hw:1,4 -f S32_LE …` works (kernel path OK)

## Install

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

## KPI chain

```text
arecord hw:1,4  →  PW Internal Microphone  →  GNOME input  →  apps
```

Verify:

```bash
alsaucm -c 1 set _verb HiFi && alsaucm -c 1 dump text | grep -A8 'Device.Mic'
wpctl status
pw-cli ls Node | grep -i microphone
```

Set default input (if needed):

```bash
wpctl status   # note Internal Microphone id
wpctl set-default <id>
```

## Rollback

```bash
sudo rm -f /usr/share/alsa/ucm2/sof-soundwire/acp-dmic.conf
sudo cp /usr/share/alsa/ucm2/conf.d/amd-soundwire/ASUSTeKCOMPUTERINC.-ProArtPX13HN7306EAC-1.0-HN7306EAC.conf.bak-snd-repair-dmic \
  /usr/share/alsa/ucm2/conf.d/amd-soundwire/ASUSTeKCOMPUTERINC.-ProArtPX13HN7306EAC-1.0-HN7306EAC.conf
systemctl --user restart wireplumber pipewire
```

## Background

[research/experiments/ucm-dmic-inspection-20260712.md](../research/experiments/ucm-dmic-inspection-20260712.md)
