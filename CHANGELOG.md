# Changelog

## Unreleased

### Product branch (`main`)

- Restructured as minimal install product (README, INSTALL, VALIDATION, PATCHES)
- Kernel patches: 0001 post-sleep hw_params reinit, 0002 AMD SoundWire resume kick
- Base upstream series A+B+C via `scripts/apply-upstream-patches.sh`
- Full investigation preserved on branch `resolution/bruteforce`

### Verified (PX13 HN7306EAC, kernel 7.0.0-27)

- Cold boot stereo playback
- Suspend/resume speaker playback (s2idle)
- Internal and headset microphone via PipeWire/GNOME
- Headphone jack playback

### Known limitations

- ALSA RW capture after S2
- Hibernate not validated

---

## Prior work

Detailed experiment timeline (2026-07-09 through 2026-07-14), W-series lab, KPI matrices, and resolution framework: see git history on **`resolution/bruteforce`**.
