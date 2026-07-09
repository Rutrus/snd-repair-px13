# Changelog

All notable changes to this repository. Kernel patch content is tracked per series under `upstream/`.

---

## [Unreleased]

### Added

- FW validation automation: `scripts/install-fw-validation-service.sh`, suspend drop-in, boot hook
- Hardened `scripts/px13-audio-fix.sh` + install/restore helpers
- Investigation tracks under `research/` (failure report, backlog, tracks A–D)
- `docs/FW-VALIDATION.md` / `docs/es/VALIDACION-FW.md`
- `.cursor/rules/documentation-english.mdc` — default docs language is English
- [`docs/PREREQUISITES.md`](docs/PREREQUISITES.md) / [`docs/es/PREREQUISITOS.md`](docs/es/PREREQUISITOS.md)
- [`docs/VERIFICATION.md`](docs/VERIFICATION.md) / [`docs/es/VERIFICACION.md`](docs/es/VERIFICACION.md)
- [`docs/ROLLBACK.md`](docs/ROLLBACK.md) / [`docs/es/REVERSION.md`](docs/es/REVERSION.md)
- [`upstream/docs/`](upstream/docs/) — English maintainer docs; Spanish in `upstream/docs/es/`
- MIT [`LICENSE`](LICENSE) with GPL-2.0-only note for kernel patches
- [`CONTRIBUTING.md`](CONTRIBUTING.md), bug report template
- `scripts/build-from-upstream.sh` — recommended production build (series A+B+C, no ENZOPLAY)

### Changed

- Documentation index prioritizes **INSTALL** over scattered stage docs
- `post-kernel-update.sh` uses `build-from-upstream.sh`
- `.gitignore` excludes `firmware/`, `*.bin`, proprietary blobs

### Security

- Verified: no proprietary `.bin` firmware in git history

---

## [0.1.0] — 2026-07-09

### Added

- Initial public release: investigation log, `patches/` (lab), `upstream/` (clean series A/B/C)
- Bilingual docs under `docs/` and `docs/es/`
- Scripts: `prepare-kernel-tree.sh`, `apply-upstream-patches.sh`, `post-kernel-update.sh`
- Validation matrix scaffold in `validation/`

### Documented problems

- **A** — capture `-EINVAL` on speaker-only TAS2783 without `source_ports`
- **B** — firmware download `-ETIMEDOUT` / `-110` (experimental retry)
- **C** — stereo playback: left channel only (channel map + `tas2783-sdw`)
