# Pre-submission review (maintainer style)

> **English** | [Español](es/MAINTAINER-REVIEW.md)

Status: 2026-07-09 — patches A/C apply cleanly on `linux-source-7.0.0`.

## checkpatch.pl --strict

| Patch | Result |
|-------|--------|
| series-A-capture/0001 | ✅ 0 errors, 0 warnings |
| series-C-channel-map/0001 | ✅ 0 errors (commit message re-wrap) |
| series-C-channel-map/0002 | ✅ 0 errors, 0 warnings |

```bash
scripts/checkpatch.pl --strict --no-tree upstream/series-A-capture/*.patch
scripts/checkpatch.pl --strict --no-tree upstream/series-C-channel-map/*.patch
```

## Recipients (MAINTAINERS 7.0)

| Role | Contact | Series |
|------|---------|--------|
| alsa-devel | alsa-devel@vger.kernel.org | A, B, C |
| ASoC | Mark Brown, Liam Girdwood | A, C |
| SoundWire | Vinod Koul, Bard Liao | B, C |
| TI codecs (`sound/soc/codecs/tas2*`) | Shenghao Ding, Kevin Lu, Baojun Xu | A, B, C |
| sdw_utils (Cirrus/Intel heritage) | Charles Keepax | C |
| AMD ASoC | Vijendar Mukunda | optional (Reported-on) |

```bash
# Example send-email (adjust identity and kernel path)
git send-email --to alsa-devel@vger.kernel.org \
  --cc shenghao-ding@ti.com --cc kevin-lu@ti.com --cc baojun.xu@ti.com \
  --cc vkoul@kernel.org --cc broonie@kernel.org \
  upstream/series-A-capture/cover-letter.txt \
  upstream/series-A-capture/0001*.patch
```

## Series A — generic message ✅

Commit focuses on **runtime SDW properties** (`source_ports == 0`), not ASUS branding.
Hardware only in `Reported-on:`.

## Series C — maintainer rebuttal

**Q: Why was `soc_sdw_utils` wrong for all codecs?**

A: Not wrong in general — `step=0` is **deliberate** for mono duplicated to N codecs.
It failed in the symmetric **capture-already-solved** case: `ch == num_codecs` with one
speaker per codec. CS35L56 avoids this via `snd_soc_dai_set_tdm_slot()` in
`soc_sdw_cs_amp.c`; TAS2783/AMD have no equivalent in `soc_sdw_ti_amp.c`.

**Q: Why not tas2783 only?**

A: After utils alone, `ch_maps` still shows `0x3` on both codecs; tas2783-only is
insufficient (proven with ENZOPLAY). Both layers are required.

**Q: Break 4-codec Intel MTL?**

A: Condition `ch == num_codecs` → masks `BIT(0..N-1)`. MTL ACPI lists 4× TAS2783 on
one link; algorithm is consistent. **Not tested on MTL hardware** — state in cover
letter (already included).

| Playback scenario | Behaviour |
|-------------------|-----------|
| 1 codec, stereo | Unchanged |
| N codecs, 1 ch (mono) | Unchanged (duplicate) |
| N codecs, ch != N | Unchanged |
| **N codecs, ch == N** | **New: BIT(i) per codec** |

## Series B — RFC + objective table

Current matrix (7 boots, pre/post patches):

| Boot | UID `:8` | UID `:b` | Audio |
|------|----------|----------|-------|
| 1 | OK | FAIL(fw) | left-only |
| 2 | OK | OK | left-only |
| 3 | OK | WARN | left-only |
| 4 | OK | FAIL(fw) | left-only |
| 5 | OK | FAIL(fw) | left-only |
| 6 | OK | OK | left-only |
| 7 | OK | OK | left-only → **L/R after series C** |

**Before 0006+0007:** `:b` FAIL ~50% (3/6 boots with FW failure).  
**Boot 7:** 0 FAIL; stereo still broken until series C.

Pending for RFC → formal patch: `VALIDATION-TODO.md` (20–30 boots, S3, rates).

## Final checklist

- [ ] Replace `Signed-off-by: ASUS ProArt PX13 debug <snd-repair@local>`
- [ ] Rebase on `linux-next` / maintainer branch
- [ ] Confirm ENZOPLAY/ENZODBG **not** in sent tree
- [ ] Send A and C; B as `[RFC PATCH]`
