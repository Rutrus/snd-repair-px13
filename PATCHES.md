# Patches overview

English · for DIY install and maintainers.

---

## Userspace (external)

| Component | Source |
|-----------|--------|
| TAS2783 firmware blobs | [brainchillz PX13 fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) |
| UCM profiles | same + `scripts/install-ucm-px13.sh` in this repo |

---

## Kernel — upstream series (in `upstream/`)

Applied by `scripts/apply-upstream-patches.sh`, built by `scripts/build-from-upstream.sh`.

| Series | Purpose |
|--------|---------|
| **A — capture** | Skip capture hw_params when codec has no source ports |
| **B — firmware** | FW download retry, wait in hw_params, reload FW after system sleep |
| **C — channel map** | One playback channel per TAS2783 (stereo L/R on dual amps) |

---

## Kernel — post-sleep playback (in `patches/`)

| Patch | Applied by | Purpose |
|-------|------------|---------|
| `0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch` | `build-upstream-post-sleep-reinit.sh` | Second `fw_reinit()` on **first hw_params** after S2 (fixes silent speakers) |

Mechanism: `resume_playback_reinit_pending` — one shot per sleep cycle. See [maintainer/DESIGN.md](maintainer/DESIGN.md).

---

## Kernel — AMD SoundWire resume (in `patches/`)

Built by `scripts/build-amd-soundwire-resume.sh`:

| Patch | Purpose |
|-------|---------|
| `0002-amd-soundwire-resume-irq-kick.patch` | Schedule SoundWire IRQ worker when masked STAT pending after resume |

---

## Full research branch

Experiment history (W-series lab, timelines, false hypotheses): branch **`resolution/bruteforce`**.
