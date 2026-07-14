# Upstream patches — ASUS ProArt PX13 / TAS2783 SoundWire

Four **independent** series. **Do not send A and C on the same day.**

| Series | Issue | Directory | When to send |
|--------|-------|-----------|--------------|
| A | Capture without `source_ports` | `series-A-capture/` | **Now** |
| C | Multicodec `ch_mask` | `series-C-channel-map/` | After maintainer review |
| B | FW `-110` | `series-B-firmware/` | RFC + 20–30 boot matrix |
| D | Investigation | branch `resolution/bruteforce` | On request |

Submission schedule, checklists, and full investigation log: branch **`resolution/bruteforce`** (`upstream/docs/`, `SUBMISSION-PLAN.md`).

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

On branch **`resolution/bruteforce`**:

- `upstream/docs/INVESTIGATION-SUMMARY.md`
- `upstream/docs/PRE-SUBMIT-CHECKLIST.md`
- `upstream/docs/MAINTAINER-REVIEW.md`
- `docs/expert-report.md` — full investigation log

On **`main`**: [maintainer/](../maintainer/) — short root cause and patch design.
