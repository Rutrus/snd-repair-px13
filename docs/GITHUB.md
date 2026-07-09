# Publish to personal GitHub

> **English** | [Español](es/GITHUB.md)

## What the repository contains

- Documentation, patches, scripts, upstream series, and validation data.
- Does **not** include the `linux-source-*` tree or source `.deb` (several GB). Each clone generates them locally.

## Steps

### 1. Initialize git (if not already)

```bash
cd ~/snd_repair
git init
git add .
git status        # confirm linux-source-* and .deb are excluded
git commit -m "Initial public release: PX13 TAS2783 audio fix and documentation"
```

### 2. Create an empty repository on GitHub

At https://github.com/new:

- Suggested name: `snd-repair-px13` or `asus-proart-px13-audio`
- **Without** README, `.gitignore`, or license (you have them locally)
- Public (documentation) or private

### 3. Link and push

Replace `YOUR_USER` and `REPO_NAME`:

```bash
git branch -M main
git remote add origin git@github.com:YOUR_USER/REPO_NAME.git
git push -u origin main
```

HTTPS:

```bash
git remote add origin https://github.com/YOUR_USER/REPO_NAME.git
git push -u origin main
```

### 4. Check size

```bash
git count-objects -vH
```

Should be a few MB. If you see hundreds of MB, `linux-source-*` was committed by mistake:

```bash
git rm -r --cached linux-source-* '*.deb' 2>/dev/null
echo "linux-source-*/" >> .gitignore
git commit --amend   # only if you have not pushed yet
```

### 5. GitHub README

Root [`README.md`](../README.md) is the repo landing page (English by default). [`README.es.md`](../README.es.md) is the Spanish variant.

## Legal notes

- Firmware binaries are **not** in this repo (ASUS/TI proprietary). Docs explain extraction from the official installer.
- Kernel patches are original contributions; `upstream/` series are intended for maintainers.

## Clone on another machine

```bash
git clone git@github.com:YOUR_USER/REPO_NAME.git
cd REPO_NAME
# Follow README.md → prepare-kernel-tree.sh → build-production-modules.sh
```
