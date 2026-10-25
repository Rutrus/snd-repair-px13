# Contributing

Thank you for helping improve Linux audio on the ASUS ProArt PX13 (and related ACP70 / TAS2783 setups).

**Full protocol (required reading for patch work):**  
→ **[docs/development-protocol.md](docs/development-protocol.md)**

---

## Quick start for contributors

1. Install prerequisites and the product overlay: [INSTALL.md](INSTALL.md).
2. Confirm live markers: `./scripts/snd-repair status`.
3. Open a PR against **`main`** (not `resolution/bruteforce`).
4. Run the smoke gate in the protocol (§8) on your ABI (`uname -r`).

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
| `research/…` | Experiments and incidents |
| `resolution/bruteforce` | Historical archive |

| Tag | Meaning |
|-----|---------|
| `overlay-<kver>` | Commit validated for that kernel ABI |
| `vMAJOR.MINOR.PATCH` | Optional product/docs release |

Add a bullet under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md) with every user-visible or rebuild-affecting change.

---

## Kernel ABI reminder

Overlay modules are **per-`uname -r`**. After a kernel upgrade, rebuild and reinstall — do not copy `.ko` from another ABI. Details: protocol §5 and [INSTALL.md](INSTALL.md) (“After kernel upgrade”).

---

## License

Docs and scripts: MIT. Kernel patches: **GPL-2.0-only**.
