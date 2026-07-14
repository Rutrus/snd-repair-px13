# Prerequisites

---

## Hardware

| Requirement | Notes |
|-------------|-------|
| **ASUS ProArt PX13 (HN7306EAC)** | AMD ACP70, 2× TAS2783 @ SoundWire |
| Kernel **7.0+** | Tested on `7.0.0-27-generic` |
| Ubuntu 26.04 / Linux Mint 22.x | Other Debian derivatives may work with adjustments |

---

## Stage 1 — brainchillz (userspace)

```bash
sudo apt install git alsa-utils pipewire pipewire-pulse wireplumber
```

Optional but useful:

```bash
sudo apt install alsa-ucm-conf   # base UCM profiles (overridden by fix script)
```

You also need:

- Proprietary firmware `.bin` files (extracted locally — not in git)
- Root/sudo for `/lib/firmware`, systemd, UCM paths

---

## Stage 2 — snd_repair (kernel build)

Installed automatically by `scripts/prepare-kernel-tree.sh`:

```bash
sudo apt install \
  build-essential flex bison libssl-dev libelf-dev dwarves bc zstd \
  linux-headers-$(uname -r) \
  linux-source-$(uname -r | cut -d- -f1-2)
```

| Package | Purpose |
|---------|---------|
| `linux-headers-$KVER` | Module build against running kernel |
| `linux-source-*` | Patched driver sources (~3 GB extracted to `build/`) |
| `dwarves` / `pahole` | BTF/debug info if enabled in kernel config |
| `zstd` | Compressed `.ko.zst` modules on Ubuntu 24.04+ |

**Disk space:** ~4 GB free under repo `build/` + kernel source extraction.

**Permissions:** sudo for `apt`, copying `.ko.zst` into `/lib/modules/`.

---

## Verification tools

```bash
sudo apt install alsa-utils   # speaker-test, aplay
```

PipeWire stack (usually preinstalled on Mint/Ubuntu desktop):

```bash
wpctl status    # from pipewire package
```

---

## Optional — upstream submission

```bash
sudo apt install git-email
# kernel tree with scripts/checkpatch.pl (from full linux git clone)
```

See branch **`resolution/bruteforce`** (`upstream/docs/`) for upstream submission checklists.

---

## Not required

| Item | Why |
|------|-----|
| DKMS | Modules are rebuilt manually via scripts |
| Custom kernel image | Only two `.ko` modules are replaced |
| Secure Boot disabled | Unless your distro blocks unsigned modules (then sign or disable) |
