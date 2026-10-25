# Changelog

## Unreleased

### Product branch (`main`)

- Repo hygiene: drop upstream cover-letter/cc/send-email + B VALIDATION-TODO; promote k28 CASE-A notes to `main`
- Archive tags: `archive/resolution-bruteforce`, `archive/research-s2idle-sdw-reattach-k28`; delete stale remotes (`product/…`, `research/suspend-lifecycle`, `resolution/lab`, old research tip)

---

## [0.4.0] — 2026-10-25

**Tag:** `v0.4.0` · **ABI tag:** `overlay-7.0.0-38`  
**Validated:** PX13 HN7306EAC · `7.0.0-38-generic` · cold-boot stereo OK · live markers OK

- Refresh upstream B-0003 for 7.0.0-38 resume (`sdw_slave_wait_for_init` + checked `regcache_sync`)
- CLI `scripts/snd`: status/check/install/reset; RT721 capture unmute; Meet HDMI-as-mic stream scrub
- `snd check-patches` + `apply-upstream-patches.sh --check` (fail-fast dry-run before long build)
- Recover helpers: `px13-pro-audio-route.sh`, `recover-post-s2-mute-no-reboot.sh`, `recover-asymmetric-amp-mute.sh`
- Troubleshooting: Post-S2 mute/mic, pro-audio jack routing, internal mic Source=sink
- Research incidents under `research/s2idle-reattach-k28/` (2026-07-27, 08-03, 08-05)
- Public contributor protocol: `CONTRIBUTING.md` + `docs/development-protocol.md` (patches, ABI, git, tags)
- Overlay install under `updates/snd_repair/` (stock in-tree untouched)
- CLI: `scripts/snd-repair` (`status`, `gate`, `build`, `install-modules`, `rollback`)
- In-repo GRUB escape hatch: `scripts/apply-kernel-safety.sh`
- Marker check in `install-modules` no longer false-negatives under `pipefail` (SIGPIPE)
- **Incident 2026-07-19:** live `PX13_AFTER_SUSPEND` PCI reset freezes machine — recover with cold power only; guard script `install-px13-pci-reset-guard.sh`
- Restructured as minimal install product (README, INSTALL, VALIDATION, PATCHES)
- Kernel patches: 0001/0001b TAS post-sleep reinit, 0002/0003/0003b AMD SoundWire resume
- Base upstream series A+B+C via `scripts/apply-upstream-patches.sh`
- Full investigation preserved on branch `resolution/bruteforce` (and `research/s2idle-sdw-reattach-k28`)

### Verified (PX13 HN7306EAC, kernel 7.0.0-27)

- Cold boot stereo playback
- Suspend/resume speaker playback (s2idle) with overlay **0001+0001b+0002+0003+0003b** on k28
- Internal and headset microphone via PipeWire/GNOME
- Headphone jack playback

### Known limitations

- ALSA RW capture after S2
- Hibernate not validated

---

## Prior work

Detailed experiment timeline (2026-07-09 through 2026-07-14), W-series lab, KPI matrices, and resolution framework: see git history on **`resolution/bruteforce`**.
