---
name: Bug report
about: Audio issue on ASUS ProArt PX13 (snd_repair)
title: "[PX13] "
labels: ""
assignees: []
---

## Environment

- **Machine model:** <!-- e.g. HN7306EAC -->
- **Kernel:** <!-- output of uname -r -->
- **Distribution:** <!-- e.g. Ubuntu 26.04 -->

## Firmware (stage 1)

- [ ] Proprietary firmware installed (`1714-1-8.bin`, `1714-1-B.bin` in `/usr/lib/firmware/`)
- [ ] Used [brainchillz firmware repo](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix)

## Kernel modules (stage 2)

- [ ] `build-from-upstream.sh` (recommended)
- [ ] `build-production-modules.sh` (investigation / ENZOPLAY)

## Symptoms

<!-- e.g. no audio, left only, -110 on reboot, capture -22 -->

## Logs

```
# paste: dmesg | grep -i tas2783
```

```
# paste: speaker-test result or wpctl status if relevant
```

## Steps to reproduce

1.
2.
3.
