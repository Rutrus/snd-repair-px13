# Clean restart — PX13 audio stack (2026-07-12)

English (canonical). Use when the stack is broken (Dummy Output, silent playback, mixed W1+W2 + px13-audio-resume, manual `px13-audio-fix` mid-session).

---

## Goal

Return to **stock kernel modules** + known-good user layer, then reinstall in documented order.

---

## 1. Stop conflicting services

```bash
sudo systemctl disable --now px13-audio-resume.service 2>/dev/null || true
sudo systemctl disable --now px13-audio-fix.service 2>/dev/null || true
```

---

## 2. Restore stock kernel modules

If you have backups from build scripts (`~/snd-soc-*.ko.zst.orig`):

```bash
KVER="$(uname -r)"
sudo cp ~/snd-soc-tas2783-sdw.ko.zst.orig \
  "/lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst" 2>/dev/null || true
sudo cp ~/soundwire-amd.ko.zst.orig \
  "/lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst" 2>/dev/null || true
sudo depmod -a
```

Or reinstall distro packages (restores all stock `.ko` for that kernel):

```bash
sudo apt install --reinstall linux-modules-$(uname -r) linux-modules-extra-$(uname -r)
sudo depmod -a
```

**Reboot** after either path.

---

## 3. Reset kernel source tree (optional, for rebuild)

```bash
./scripts/reset-kernel-tree.sh
./scripts/prepare-kernel-tree.sh
./scripts/apply-upstream-patches.sh
```

---

## 4. Fresh install order

See [`docs/INSTALL.md`](../docs/INSTALL.md) or [`README.md`](../../README.md) — practical stack section.

```text
brainchillz (firmware + UCM)
→ build-from-upstream.sh + reboot
→ build-w1-w2.sh + reboot
→ install-ucm-px13.sh
→ verify: speaker-test -D pipewire …
→ post-s2-user-witness.sh (TTY, ear confirm)
```

**Do not** mix `px13-audio-resume.service` with W1+W2 without reading [post-s2-silent-playback-recovery-20260712.md](experiments/post-s2-silent-playback-recovery-20260712.md).

---

## 5. W3 diagnostic (laboratory only)

If continuing silent-playback investigation after clean base:

```bash
sudo ./scripts/build-w3-dapm-probe.sh
sudo reboot
```

Not required for daily use.

---

## What we learned before pause (2026-07-12)

| Finding | Doc |
|---------|-----|
| Silent playback post-S2 with PCM RUNNING + hw_ptr | [silent-playback-dapm-fu-mute-20260712.md](experiments/silent-playback-dapm-fu-mute-20260712.md) |
| W3 Exp A: POST_PMU fires, FU_MUTE=0, still silent | [w3-experiment-a-20260712.md](experiments/w3-experiment-a-20260712.md) |
| Dummy Output from W1+W2 + px13-audio-resume | [post-s2-silent-playback-recovery-20260712.md](experiments/post-s2-silent-playback-recovery-20260712.md) |

Reversal detail: [`docs/es/REVERSION.md`](../docs/es/REVERSION.md)
