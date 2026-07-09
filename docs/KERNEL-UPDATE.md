# Replicate the fix after a kernel upgrade

> **English** | [Español](es/ACTUALIZACION-KERNEL.md)

**Theoretical document:** strategies to keep audio working whenever Ubuntu installs a new kernel (`linux-image-*`, `linux-headers-*`).

---

## Why the process must be repeated

Patched modules (`snd-soc-tas2783-sdw.ko`, `snd-soc-sdw-utils.ko`) are built against a specific **vermagic**. After `apt upgrade`:

1. The running kernel changes (or will after reboot).
2. `.ko` files under `/lib/modules/OLD_VERSION/` **do not load** on the new version.
3. You fall back to the vanilla stack → `-22`, `-110`, or mono may return.

**Firmware** in `/usr/lib/firmware/` does **not** depend on the kernel: install once (unless a clean reinstall).

---

## Minimal repeatable flow (manual)

```
apt upgrade → new kernel KVER
     ↓
reboot (optional: boot the new kernel)
     ↓
prepare-kernel-tree.sh      # sources aligned with KVER
     ↓
build-production-modules.sh # patches 0004+0006+0007+0009
     ↓
reboot
     ↓
verify: speaker-test / dmesg | grep -i tas2783
```

Estimated time: 5–15 min (compile on PX13).

---

## Automation strategies

### A — Post-update script (recommended for a single machine)

**Idea:** hook that detects new kernels without patched modules.

| Component | Role |
|-----------|------|
| `scripts/build-production-modules.sh` | Build and install for `uname -r` |
| `scripts/post-kernel-update.sh` | Check for patched `.ko`; rebuild if missing |
| Trigger | `apt` hook (`/etc/apt/apt.conf.d/`) or `@reboot` cron |

**Pros:** simple, no DKMS, full control.  
**Cons:** requires `linux-headers-$(uname -r)` and `build-essential`.

```
/etc/apt/apt.conf.d/99-snd-repair
  → DPkg::Post-Invoke runs post-kernel-update.sh when linux-image changes
```

### B — DKMS

**Idea:** package patched source as DKMS modules; new headers trigger automatic rebuild.

| Step | Action |
|------|--------|
| 1 | Create `/usr/src/snd-repair-tas2783-1.0/` with patched sources + `dkms.conf` |
| 2 | `dkms add` / `dkms build` / `dkms install` |
| 3 | Each `apt install linux-headers-*` triggers rebuild |

**Pros:** Ubuntu standard, `dkms autoinstall` integration.  
**Cons:** two modules (tas2783 + sdw_utils), more packaging work; patch 0009 touches two trees.

### C — Local `.deb` package (`debian/`)

**Idea:** `debian/rules` applies patches, builds against `linux-headers-$KVER`, ships `.ko.zst`.

**Pros:** reproducible, versioned, `dpkg -i` install.  
**Cons:** one `.deb` per kernel version, or DKMS inside the package.

### D — Wait for upstream merge

**Idea:** when series A/C/B in [`upstream/`](../upstream/README.md) land in stable kernel, local modules are no longer needed.

**Pros:** zero maintenance once included.  
**Cons:** uncertain timeline; use local B/C until then.

### E — Dual boot: “frozen” kernel

**Idea:** keep a GRUB entry with the last **validated** kernel + prebuilt modules.

**Pros:** fallback if a new kernel breaks audio.  
**Cons:** not a permanent fix; old kernels lose security support.

---

## Decision matrix

| Criterion | Manual | apt hook | DKMS | Own .deb | Upstream |
|-----------|--------|----------|------|----------|----------|
| Initial effort | Low | Medium | High | High | None (wait) |
| Maintenance | High | Medium | Low | Medium | None |
| After each kernel | Manual | Semi-auto | Auto | Semi-auto | Nothing |
| Portability | One PC | One PC | Good | Good | Universal |

**Practical recommendation for PX13:**

1. **Short term:** `build-production-modules.sh` + reminder after `apt upgrade` (or apt hook).
2. **Medium term:** DKMS package if you upgrade kernels often.
3. **Long term:** contribute upstream and drop local patches when merged.

---

## Checklist after each kernel upgrade

- [ ] `uname -r` matches the kernel you intend to use
- [ ] `linux-headers-$(uname -r)` installed
- [ ] `prepare-kernel-tree.sh` completed without error
- [ ] `build-production-modules.sh` installed both `.ko.zst` files
- [ ] `modinfo snd_soc_tas2783_sdw | grep vermagic` matches `uname -r`
- [ ] `dmesg | grep -i tas2783` shows no `error playback without fw` or `-22`
- [ ] `speaker-test` L and R separately

---

## What you do **not** repeat

| Item | Repeat? |
|------|---------|
| Firmware `/usr/lib/firmware/` | No |
| PipeWire/Pulse config | No |
| Patches in repo (`patches/`) | No (only re-apply to new source tree) |
| 20–30 boot validation (Series B) | Only if hardware or base driver changes |
