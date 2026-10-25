# Contributing

Thank you for helping improve Linux audio on the ASUS ProArt PX13 (and related ACP70 / TAS2783 setups).

**Full protocol (required reading for patch work):**  
→ **[docs/development-protocol.md](docs/development-protocol.md)**

---

## Quick start for contributors

1. Install prerequisites and the product overlay: [INSTALL.md](INSTALL.md).
2. Confirm live markers: `./scripts/snd-repair status`.
3. Before a long rebuild on a new ABI: `snd check-patches` (dry-run A+B+C; fails fast if a hunk drifted).
4. Open a PR against **`main`** (not `resolution/bruteforce`).
5. Run the smoke gate in the protocol (§8) on your ABI (`uname -r`).

---

## What belongs where

| Change type | Put it in |
|-------------|-----------|
| Clean driver fix (upstream-shaped) | `upstream/series-A|B|C/` |
| Post-S2 product resume / SDW kick | `patches/` + apply scripts; markers in `.ko` |
| Install / recover UX | `scripts/`, `INSTALL.md`, `docs/troubleshooting.md` |
| Failure write-up | `research/<track>/INCIDENT-YYYYMMDD-….md` (English) |

Do **not** collapse research hypotheses into product patches without evidence.  
Do **not** recommend live PCI reset of `0000:c4:00.5` (hard freeze risk).

---

## Branches and tags

| Branch | Use |
|--------|-----|
| `main` | Default product; open PRs here |
| `research/…` | Short-lived experiments (merge notes into `main` when useful) |
| `resolution/bruteforce` | Historical lab archive (optional local checkout) |

| Tag | Meaning |
|-----|---------|
| `overlay-<kver>` | Commit validated for that kernel ABI |
| `vMAJOR.MINOR.PATCH` | Optional product/docs release |
| `archive/resolution-bruteforce` | Frozen lab notebook tip |
| `archive/research-s2idle-sdw-reattach-k28` | Frozen k28 research tip (notes also on `main`) |

Add a bullet under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md) with every user-visible or rebuild-affecting change.

---

## Kernel ABI reminder

Overlay modules are **per-`uname -r`**. After a kernel upgrade, rebuild and reinstall — do not copy `.ko` from another ABI. Details: protocol §5 and [INSTALL.md](INSTALL.md) (“After kernel upgrade”).

Local regenerable junk (gitignored): `build/linux-source`, old `build/staging/<other-abi>/`, `linux-source-*.deb`, `validation/` (may need `sudo rm -rf` if created as root).

---

## License

Docs and scripts: MIT. Kernel patches: **GPL-2.0-only**.
