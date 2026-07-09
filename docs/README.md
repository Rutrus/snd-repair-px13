# Documentation — snd_repair

> **English** | [Español](es/README.md)

## Start here

| Doc | Content |
|-----|---------|
| **[INSTALL.md](INSTALL.md)** | **Full install** — brainchillz (firmware/UCM/systemd) + kernel modules |
| [PREREQUISITES.md](PREREQUISITES.md) | Packages, disk space, hardware |
| [VERIFICATION.md](VERIFICATION.md) | Post-install checklist |
| [ROLLBACK.md](ROLLBACK.md) | Restore stock modules and userspace |
| [KERNEL-UPDATE.md](KERNEL-UPDATE.md) | After `apt upgrade` |
| [FW-VALIDATION.md](FW-VALIDATION.md) | **Boot matrix** — auto/manual logging (Serie B) |

## Overview and analysis

| # | File | Content |
|---|------|---------|
| 1 | [SUMMARY.md](SUMMARY.md) | One page: stages, problems A/B/C, outcome |
| 2 | [SOLUTION.md](SOLUTION.md) | Timeline and lessons learned |
| 3 | [TECHNICAL-REVIEW.md](TECHNICAL-REVIEW.md) | Maintainer-style review: facts vs hypotheses |
| 4 | [expert-report.md](expert-report.md) | Full investigation log (ENZOPLAY traces) |

## Stage guides (also covered in INSTALL)

| File | Content |
|------|---------|
| [01-firmware-installation.md](01-firmware-installation.md) | Extract proprietary ASUS firmware |
| [../patches/README.md](../patches/README.md) | Laboratory patches (debug) |
| [../upstream/README.md](../upstream/README.md) | Clean upstream series A/B/C |

## Technical reference

| File | Content |
|------|---------|
| [fw-analysis.md](fw-analysis.md) | TAS2783 firmware matrix analysis |
| [firmware-data.md](firmware-data.md) | Extraction data / symlink matrix |
| [firmware-pre-reboot.md](firmware-pre-reboot.md) | Pre-reboot state *(historical)* |

## Publishing

| File | Content |
|------|---------|
| [GITHUB.md](GITHUB.md) | Publish to GitHub |

## Upstream maintainer docs

| Location | Content |
|----------|---------|
| [../upstream/docs/INVESTIGATION-SUMMARY.md](../upstream/docs/INVESTIGATION-SUMMARY.md) | Short investigation summary |
| [../upstream/docs/PRE-SUBMIT-CHECKLIST.md](../upstream/docs/PRE-SUBMIT-CHECKLIST.md) | Genericity / regression checklist |
| [../upstream/docs/SERIE-C-DEFENSE.md](../upstream/docs/SERIE-C-DEFENSE.md) | Series C rebuttal notes |
| [../validation/README.md](../validation/README.md) | Boot matrix (Problem B, -110) |
