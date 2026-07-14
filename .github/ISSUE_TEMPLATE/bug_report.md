---
name: Bug report
about: Audio issue on ASUS ProArt PX13 (snd-repair-px13)
title: "[PX13] "
labels: ""
assignees: []
---

## Environment

- **Machine model:** <!-- e.g. HN7306EAC -->
- **Kernel:** <!-- `uname -r` -->
- **Distribution:** <!-- e.g. Ubuntu 26.04 -->

## Install checklist

- [ ] Firmware installed via [brainchillz](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) (`1714-1-8.bin`, `1714-1-B.bin`)
- [ ] `apply-upstream-patches.sh` + `build-from-upstream.sh`
- [ ] `build-upstream-post-sleep-reinit.sh` (patch 0001)
- [ ] `build-amd-soundwire-resume.sh` (patch 0002)
- [ ] `px13-audio-resume.service` **disabled** (required with kernel patches)
- [ ] `modinfo snd_soc_tas2783_sdw | grep vermagic` matches `uname -r`

See [INSTALL.md](../INSTALL.md) · [VALIDATION.md](../VALIDATION.md)

## Symptoms

<!-- e.g. no audio, left only only, silent after suspend, Dummy Output, mic missing -->

- **When:** <!-- cold boot / after suspend / after kernel upgrade -->
- **PipeWire or ALSA direct:**

## Logs

```
# journalctl -k -b 0 | grep -iE 'tas2783|soundwire|amd'
```

```
# wpctl status
```

## Steps to reproduce

1.
2.
3.

## Expected vs actual

<!-- What should happen vs what happens -->
