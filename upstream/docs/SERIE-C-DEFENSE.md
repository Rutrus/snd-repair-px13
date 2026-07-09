# Series C — pre-submit validation (maintainer rebuttal)

> **English** | [Español](es/SERIE-C-DEFENSA.md)

Internal document. **Do not send as a patch**; use to draft cover letter and rebuttals.

## Expected question

> Why was `snd_soc_sdw_utils` wrong for all codecs and not only TAS2783?

## Short answer

We do not claim `step=0` is a universal bug. We claim the **symmetric-to-capture** case is
missing when `channels == num_codecs` in playback: one PCM channel per physical codec.
Capture already models this; playback always used `step=0` by original design.

## Two layers (both required)

| Layer | Problem without patch | Evidence |
|-------|----------------------|----------|
| `asoc_sdw_hw_params()` | `ch_maps[i].ch_mask = 0x3` for all | ENZOPLAY `step=0` |
| `tas2783-sdw.c` | `snd_sdw_params_to_config()` → full mask; ignores `ch_maps` | `include/sound/sdw.h` documents explicit override |

**tas2783 only** is insufficient: with utils unchanged, `ch_map->ch_mask` stays `0x3` on both codecs.

**utils only** is insufficient: TAS2783 programmed `port_config.ch_mask=0x3` even when `ch_maps` was correct (post-0009 traces).

## Historical origin of `step=0`

| Fact | Source |
|------|--------|
| `asoc_sdw_hw_params()` born in Intel `sof_sdw` with *"Identical data will be sent to all codecs in playback"* | [alsa-devel msg159888](https://www.spinics.net/lists/alsa-devel/msg159888.html) |
| Logic moved to `soc_sdw_utils.c` (shared AMD/Intel) | [lkml 2024 — move sdw soc ops](https://lkml.indiana.edu/2408.0/00369.html) |
| Capture: split with `ch_mask << (i * step)` when `ch % num_codecs == 0` | Current `soc_sdw_utils.c` L1184–1203 |
| Playback: always `step=0` → identical mask | Intentional for mono duplicated to N amps |

**Conclusion:** `step=0` solved *mono on all codecs*. It did not cover *N channels / N codecs / one speaker per codec*.

## Algorithmic precedent (same function)

When `ch == num_codecs`, the capture branch would use:

```text
ch_mask = GENMASK(ch / num_codecs - 1, 0)  → BIT(0)
step    = 1
ch_maps[i].ch_mask = BIT(0) << i           → BIT(i)
```

Series C applies **exactly that mask** in playback for `ch == num_codecs`, without touching other cases.

## Multicodec precedents in ASoC (non-SDW)

| Pattern | Location | Relevance |
|---------|----------|-----------|
| `snd_soc_dai_set_tdm_slot(codec, 0x01)` / `0x02` per amp | `sound/soc/intel/avs/boards/ssm4567.c` | One slot per speaker |
| `set_tdm_slot` with mask per codec | `soc_sdw_cs_amp.c` (CS35L56 feedback) | SDW multicodec uses per-codec mask, not utils playback |
| CPU fixup via `ch_maps` | `soc-pcm.c` `__soc_pcm_hw_params()` | Ecosystem **trusts** `ch_maps`; SDW codec must align |

TI TAS2783 has **no** `set_tdm_slot` in `soc_sdw_ti_amp.c` (DAPM L/R only). Depends on `ch_maps` + `port_config.ch_mask`.

## Regression scope (table)

| Topology | `ch` | `num_codecs` | Before | After Series C |
|----------|------|--------------|--------|----------------|
| Mono → 2 amps | 1 | 2 | `0x1` both | **same** (not `ch==num_codecs`) |
| Stereo → 1 amp | 2 | 1 | `0x3` | **same** |
| Stereo → 2 amps (PX13) | 2 | 2 | `0x3` both | `0x1` / `0x2` ✅ validated |
| 4ch → 4 amps (MTL ACPI) | 4 | 4 | `0xf` all | `0x1`…`0x8` — **code reviewed, HW not tested** |
| 4ch → 2 amps | 4 | 2 | `0x3` both | **same** |

Intel MTL: `tas2783_0_adr[]` with 4 devices (`soc-acpi-intel-mtl-match.c`). Algorithm scales linearly.

## Checks before sending Series C

- [ ] Re-read `git blame` / `git log` on full torvalds/linux clone (local tree may not be git)
- [ ] Optional: test on 4-way hardware if available
- [ ] Confirm no SDW profile uses `ch==num_codecs` in playback **expecting** duplicated stereo (search multicodec ACPI tables)

## Recommended send order

1. **Series A** — now
2. Wait ~3–5 days / feedback
3. **Series C** — with this document internalized in cover letter
4. **Series B** — RFC + reliability table (see `series-B-firmware/VALIDATION-TODO.md`)
