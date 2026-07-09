# Documentation — snd_repair

> **English** | [Español](es/README.md)

## Recommended reading order

| # | File | Content |
|---|------|---------|
| 1 | [SUMMARY.md](SUMMARY.md) | One page: stages, problems A/B/C, outcome |
| 2 | [SOLUTION.md](SOLUTION.md) | Timeline and lessons learned |
| 3 | [01-firmware-installation.md](01-firmware-installation.md) | **Stage 1:** extract and install ASUS firmware |
| 4 | [../patches/README.md](../patches/README.md) | **Stage 2:** kernel patches, build, install |
| 5 | [KERNEL-UPDATE.md](KERNEL-UPDATE.md) | Keep the fix after `apt upgrade` |
| 6 | [GITHUB.md](GITHUB.md) | Publish to GitHub |
| 7 | [TECHNICAL-REVIEW.md](TECHNICAL-REVIEW.md) | Maintainer-style review: facts vs hypotheses, upstream strategy |

## Technical reference

| File | Content |
|------|---------|
| [TECHNICAL-REVIEW.md](TECHNICAL-REVIEW.md) | Maintainer synthesis (recommended before upstream review) |
| [expert-report.md](expert-report.md) | Full investigation log, ENZOPLAY traces |
| [fw-analysis.md](fw-analysis.md) | TAS2783 firmware matrix analysis |
| [firmware-data.md](firmware-data.md) | Extraction data / symlink matrix |
| [firmware-pre-reboot.md](firmware-pre-reboot.md) | Pre-reboot state (historical) |

## Upstream and validation

| Location | Content |
|----------|---------|
| [../upstream/README.md](../upstream/README.md) | Patches for `alsa-devel` (series A, B, C) |
| [../validation/README.md](../validation/README.md) | Boot matrix (Problem B, -110) |
