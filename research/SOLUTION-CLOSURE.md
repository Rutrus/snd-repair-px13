# Solution closure — post-S2 speaker playback

**2026-07-14** · ASUS ProArt PX13 · English

---

## Problem

Built-in speakers **silent after suspend** despite PCM running and firmware `ret=0`.

## Fix

One additional `tas2783_fw_reinit()` on the **first `hw_params`** after system sleep (`resume_playback_reinit_pending`, one shot per cycle).

## Install

[INSTALL.md](../INSTALL.md) · patch: [patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch](../patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch)

## Validated

- First `hw_params` hook: stereo L+R with no artificial delay  
- Upstream candidate module: S2 PASS + clean reinstall from commit  

## Why it works (short)

Resume-path reinit runs before the first real playback stream is configured. The same reinit at `hw_params` runs with stream/DAPM/port context ready.

## Maintainer

[maintainer/ROOT_CAUSE.md](../maintainer/ROOT_CAUSE.md) · [maintainer/DESIGN.md](../maintainer/DESIGN.md)

## Full investigation

Branch **`resolution/bruteforce`** — all experiments, timelines, and lab scripts.
