# PCM2 hw_params — kernel code path (PX13 / kernel 7.0.0)

English (canonical). Static analysis complement to `pcm-hwparams-trace.sh`.

Source tree: `/usr/src/linux-source-7.0.0/` (matches running `7.0.0-27-generic`).

---

## Userspace → kernel entry

```text
aplay / speaker-test
    ↓
snd_pcm_open()                    sound/core/pcm_native.c
    ↓
snd_pcm_hw_params()               (SNDRV_PCM_IOCTL_HW_PARAMS)
    ↓
constrain_* + hw_params_choose    pcm_native.c (~289–711)
    ↓  (-EINVAL if runtime->hw_constraints empty / no valid combo)
soc_pcm_hw_params()               sound/soc/soc-pcm.c:1172
    ↓
__soc_pcm_hw_params()             soc-pcm.c:1070
```

---

## ASoC chain for `hw:1,2` (SmartAmp / multicodec-2)

PCM name from machine driver:

```text
SDW1-PIN1-PLAYBACK-SmartAmp multicodec-2
```

Built in `sound/soc/amd/acp/acp-sdw-legacy-mach.c` (`type_strings[]` → `"SmartAmp"`).

```text
__soc_pcm_hw_params()
    │
    ├─ snd_soc_link_hw_params()          soc-link.c:98
    │      └─ dai_link->ops->hw_params
    │             = asoc_sdw_hw_params    acp-sdw-legacy-mach.c:145
    │
    ├─ for_each codec_dai:
    │      snd_soc_dai_hw_params(codec_dai)
    │             └─ tas2783: tas_sdw_hw_params   tas2783-sdw.c:893
    │                (×2 codecs on multicodec link: tas2783-1, tas2783-2)
    │
    └─ for_each cpu_dai:
           snd_soc_dai_hw_params(cpu_dai)  (+ DAPM update)
```

**PCM0 (SimpleJack)** uses RT721 DAI — different codec, same framework, explains asymmetry.

---

## `-EINVAL` candidates (ranked for post-resume PCM2)

### A — `tas2783-sdw.c:tas_sdw_hw_params()` (most documented in this repo)

| Line | Condition | Message |
|------|-----------|---------|
| ~906 | `!tas_dev->fw_dl_success` | `error playback without fw download` |
| ~912 | `!sdw_stream` | (silent) |
| ~948 | `sdw_stream_add_slave()` fail | `Unable to configure port` |

**Resume gap (stock 7.0.0):** no `tas2783_fw_reinit()` on system resume. Patches in repo:

- `patches/0007-tas2783-hw-params-wait-fw.patch` — wait in hw_params
- `upstream/series-B-firmware/0003-...` — invalidate FW flags on suspend + reinit on resume/hw_params

After s2idle, `fw_dl_success` may be **stale false** while SoundWire still shows `ATTACHED` and ENZODBG reports `fw_ok=1` at PM layer — **verify with dmesg string** on failed `aplay`.

### B — `soc_sdw_utils.c:asoc_sdw_hw_params()` (machine link op)

| Line | Condition | Notes |
|------|-----------|-------|
| ~1187 | capture + invalid channel count | **Playback** path sets `ch_mask = GENMASK(ch-1,0)` and returns 0 |
| ~1155 | trigger path | not hw_params |

Unlikely for **playback** S16_LE 2ch unless mis-routed capture stream.

### C — `soc-pcm.c` runtime intersection

| Line | Condition | Message |
|------|-----------|---------|
| ~845 | `soc_pcm_check_hw_cfg()` | `No matching formats/rates/channels` |
| ~701–715 | `soc_pcm_init_runtime_hw()` | intersects CPU∩codec `snd_pcm_hardware` at **open** |

If multicodec codec DAIs report **zero** `formats`/`rates` after resume → constraints empty → ALSA core `constrain_mask_params` → `-EINVAL` **before** `tas_sdw_hw_params`.

### D — ALSA core only

`pcm_native.c:302` — `snd_mask_empty(m)` during constrain.

Typical when `runtime->hw.formats == 0` or constraints rule out S16_LE|48000|2ch.

---

## What code review says about your symptom

| Observation | Code interpretation |
|-------------|---------------------|
| PCM0 OK, PCM2 EINVAL | Different **codec DAIs** (rt721 vs tas2783×2), not PCI/SoundWire bus |
| Fails at `set_params`, pre-DMA | Matches `hw_params` phase — no `trigger`, no `sdw_stream_add_slave` success required yet |
| remove/rescan unchanged | State is **logical** (FW flags, DAPM, stream runtime), not enumeration |
| `fw_ok=1` in SW logs but ALSA fails | Suspect **stale `fw_dl_success`** or **empty hw constraints**, not missing slave |

---

## Grep commands (on installed sources)

```bash
K=/usr/src/linux-source-7.0.0

# All EINVAL in SmartAmp codec
rg -n 'EINVAL' $K/sound/soc/codecs/tas2783-sdw.c

# Machine link ops
rg -n 'hw_params|SmartAmp|asoc_sdw' $K/sound/soc/amd/acp/acp-sdw-legacy-mach.c

# Multicodec utils
rg -n 'EINVAL|hw_params' $K/sound/soc/sdw_utils/soc_sdw_utils.c

# ASoC PCM core
rg -n 'soc_pcm_hw_params|soc_pcm_check_hw_cfg' $K/sound/soc/soc-pcm.c
```

---

## Dual-path trace (control + fail)

Same resume, same card — probe **PCM0 then PCM2** and compare dmesg. First divergence identifies where RT721 and TAS2783 paths stop being equivalent.

```bash
sudo resolution/scripts/pcm-hwparams-trace.sh --label S0 --dual-path
sudo resolution/scripts/s2-reproduce.sh
sudo resolution/scripts/pcm-hwparams-trace.sh --label S2 --dual-path
sudo dmesg | tail -80 | rg -i 'playback without fw|Unable to configure|No matching|hw_params|tas2783|rt721'
```

See [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md) · [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md).

---

## Correlate with one run (runtime)

```bash
sudo resolution/scripts/pcm-hwparams-trace.sh --label S2 --dual-path
sudo dmesg | tail -40 | rg -i 'playback without fw|Unable to configure|No matching|hw_params|tas2783'
```

| dmesg hit | Likely function |
|-----------|-----------------|
| `error playback without fw download` | `tas_sdw_hw_params` :906 |
| `Unable to configure port` | `sdw_stream_add_slave` :948 |
| `No matching formats` / `rates` / `channels` | `soc_pcm_check_hw_cfg` :845 |
| (no driver line) | ALSA constrain or DAPM-narrowed empty mask |

---

## Repo patches vs stock kernel

| Patch | Addresses |
|-------|-----------|
| `0004` capture skip | capture `hw_params` EINVAL on PIN4 (different PCM) |
| `0007` fw wait in hw_params | race at **boot** |
| `0003` series-B fw reload after sleep | **resume stale `fw_dl_success`** — directly targets S2 class |

Stock `7.0.0` tree at `tas2783-sdw.c:906` still has bare `if (!fw_dl_success) return -EINVAL` without resume reinit.

---

## Related

- [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md) — facts vs inference
- [pcm-s2-set-params-witness.md](pcm-s2-set-params-witness.md) — runtime evidence
- [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md) — active protocol
