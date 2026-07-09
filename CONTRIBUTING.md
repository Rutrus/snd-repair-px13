# Contributing

> **English** | [Español](docs/es/CONTRIBUTING.md)

Thank you for improving snd_repair. This project targets the ASUS ProArt PX13 (HN7306EAC) but may help similar ACP70 + TAS2783 setups.

## Before you open an issue

Include:

- `uname -r`
- Machine model (e.g. HN7306EAC)
- Whether proprietary firmware is installed (`ls -lh /usr/lib/firmware/1714-1-*.bin`)
- `dmesg | grep -i tas2783` (last boot)
- Which build path you used: `build-from-upstream.sh` (recommended) or `build-production-modules.sh`

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md).

## Patch workflow

### End users (recommended)

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
```

Applies clean series under `upstream/` (no `ENZOPLAY` / `ENZODBG`).

### Investigation / reproducing traces

Use `patches/0001–0009` and `build-production-modules.sh`. Patch **0009** includes debug printk — not for production systems.

### Submitting to Linux kernel

Patches in `upstream/` are formatted for `alsa-devel`. When preparing submissions:

1. Use a **real** `Signed-off-by: Your Name <email@example.com>` (Developer Certificate of Origin).
2. Kernel patches are **GPL-2.0-only** when applied to Linux (see [LICENSE](LICENSE)).
3. Run `scripts/checkpatch.pl` or follow `upstream/docs/PRE-SUBMIT-CHECKLIST.md`.
4. Series B (firmware `-110`) should be sent as **RFC** until validation matrix is expanded.

Replace placeholder `snd-repair@local` in patch headers before sending upstream.

## Pull requests

- Keep documentation bilingual when changing user-facing docs (`docs/` + `docs/es/`).
- Do not commit `linux-source-*`, `.deb` packages, firmware `.bin` files, or ACPI dumps.
- Prefer extending `upstream/` for clean fixes; keep `patches/` for investigation history.

## Code of conduct

Be technical and evidence-based in discussions, consistent with [`docs/TECHNICAL-REVIEW.md`](docs/TECHNICAL-REVIEW.md).
