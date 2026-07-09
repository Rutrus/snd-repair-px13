# Upstream patches — ASUS ProArt PX13 / TAS2783 SoundWire

> **English** | [Español](README.es.md)

Four **independent** series. **Do not send A and C on the same day.**

| Series | Issue | Directory | When to send |
|--------|-------|-----------|--------------|
| A | Capture without `source_ports` | `series-A-capture/` | **Now** |
| C | Multicodec `ch_mask` | `series-C-channel-map/` | After `docs/SERIE-C-DEFENSA.md` |
| B | FW `-110` | `series-B-firmware/` | RFC + 20–30 boot matrix |
| D | Investigation | `docs/` | On request |

See **`SUBMISSION-PLAN.md`** for schedule, recipients, and checkpatch.

## Apply (on vanilla tree, e.g. linux 6.15+ / 7.0)

```bash
KERNEL=/path/to/linux
cd "$KERNEL"

# Series A
git am ~/snd_repair/upstream/series-A-capture/*.patch

# Series C (independent of A and B)
git am ~/snd_repair/upstream/series-C-channel-map/*.patch

# Series B — only after extended validation
git am ~/snd_repair/upstream/series-B-firmware/*.patch
```

**Cross-series dependencies:** none required. A and C are complementary (capture vs playback). B is orthogonal.

Regenerate raw diffs: `./scripts/generate-upstream-patches.sh`

## Suggested recipients

- **A, C:** `alsa-devel@vger.kernel.org`, CC Senthil Kumaran S (TI), Charles Keepax (Cirrus/sdw_utils)
- **B:** `[RFC PATCH]` until boot matrix is complete

## Documentation (Series D)

- `docs/INVESTIGATION-SUMMARY.md` — timeline, ruled-out hypotheses, evidence
- `docs/PRE-SUBMIT-CHECKLIST.md` — four pre-submit questions per series
- `docs/MAINTAINER-REVIEW.md` — checkpatch, recipients, series C FAQ, FW matrix
- [`../docs/TECHNICAL-REVIEW.md`](../docs/TECHNICAL-REVIEW.md) — maintainer-style review (facts vs hypotheses)
- [`../docs/expert-report.md`](../docs/expert-report.md) — full investigation log (750+ lines)
