# Development protocol — snd_repair

English · canonical maintainer and contributor rules for patches, git, ABI upgrades, and releases.

This is the **public source of truth**. Cursor agents also load a short mirror under `.cursor/rules/development-protocol.mdc`.

Companions: [PATCHES.md](../PATCHES.md) · [INSTALL.md](../INSTALL.md) · [VALIDATION.md](../VALIDATION.md) · [CHANGELOG.md](../CHANGELOG.md) · [troubleshooting](troubleshooting.md) · [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## 1. Goals

1. Ship a **reproducible overlay** under `updates/snd_repair/` without mutating stock in-tree modules.
2. Keep base driver fixes **upstream-shaped** (`upstream/`) separate from product resume hardening (`patches/` + `scripts/apply-*.py`).
3. Survive **every kernel ABI bump** with an explicit rebuild + reboot gate.
4. Record **why** changes exist (PATCHES, CHANGELOG, research incidents) — not only what changed.

---

## 2. Layer model (do not collapse)

| Layer | Path | Allowed | Forbidden |
|-------|------|---------|-----------|
| **A+B+C base** | `upstream/series-*/` | Clean unified diffs; one concern per series | Lab strings, `ENZOPLAY`, PCI reset hacks |
| **Product 0001…0003b** | `patches/` + `scripts/apply-*.py` | Resume / enum / open-stream fixes; **string markers** in `.ko` | Third delayed `fw_reinit` without lifecycle evidence |
| **Userspace recover** | `scripts/snd`, `px13-pro-audio-route.sh`, recover-*.sh | PipeWire/UCM/mixer; SDW slave rebind only with explicit sudo | Live PCI unbind of `0000:c4:00.5` |
| **Research** | `research/**` | Evidence-backed English notes | Treating hypotheses as product patches |

**Hard safety:** never recommend live `PX13_AFTER_SUSPEND` / PCI reset of the audio function — hard freeze risk. Prefer PipeWire reopen, `pro-audio` route, or documented SDW rebind scripts.

---

## 3. Patch authoring

### Before editing

```bash
./scripts/snd-repair status
./scripts/reset-kernel-tree.sh
```

Work against **current** `/usr/src/linux-source-*` matching headers for `$(uname -r)`.

### Rules for `upstream/*.patch`

1. Git-style header (`From`, `Subject`, short body, `Signed-off-by` local OK).
2. **One logical change** per file; series order A → B → C.
3. Must apply with `patch -p1 --forward` on a **fresh** reset tree.
4. Hunk fails after kernel bump → **rewrite the patch**; never leave a half-applied tree.
5. No debug `printk` spam; product markers belong in 0001/0001b/0002/0003/0003b paths.
6. After editing: `./scripts/reset-kernel-tree.sh && ./scripts/apply-upstream-patches.sh` must exit 0 before build.

### Rules for product patches (0001+)

1. Prefer existing apply scripts (`apply-upstream-post-sleep-hw-params.py`, `apply-0001b-…`, build-amd scripts).
2. Every live fix needs a **stable marker string** checked by `scripts/lib/modules.sh`.
3. Do not add another delayed `fw_reinit` for Scenario 2 mute without PCM lifecycle contrast (Case A′′ research).
4. Update [PATCHES.md](../PATCHES.md) when adding a new numbered patch.

### Predict apply failure (before a long build)

```bash
snd check-patches
# or: ./scripts/reset-kernel-tree.sh && ./scripts/apply-upstream-patches.sh --check
```

Exit 0 ⇒ A+B+C dry-run cleanly on this ABI’s `linux-source`. Exit 1 ⇒ refresh the failing `.patch` (§ below) **before** `snd-repair build`. `snd install` runs this preflight automatically when staging is empty.

### Regenerating a broken hunk (kernel bump)

```text
snd check-patches          # fail fast
→ edit semantics / refresh context
→ diff -u before after → replace .patch
→ snd check-patches        # must exit 0
→ build staging → verify markers (zstdcat | strings)
```

---

## 4. Build, markers, install

```bash
./scripts/snd-repair build
sudo ./scripts/snd-repair install-modules
sudo reboot
./scripts/snd-repair status    # live patches: OK
```

Shortcut: `snd` / `snd install` (see `scripts/snd`). Non-interactive: `SND_YES=1 snd` or `snd install`.

| Check | Expect |
|-------|--------|
| Staging | `build/staging/$(uname -r)/{snd-soc-tas2783-sdw,soundwire-amd,snd-soc-sdw-utils}.ko.zst` |
| Markers | 0001, 0001b on TAS; 0002, 0003, 0003b on `soundwire-amd` |
| Live | `modinfo` paths under `updates/snd_repair/` |

**Never** copy `.ko` across ABIs. Staging and overlay are per-`uname -r`.

---

## 5. Kernel ABI policy

| Claim | Truth |
|-------|--------|
| Same upstream minor (e.g. 7.0.x) | Source patches *may* apply; not guaranteed |
| Same ABI (`7.0.0-38-generic`) | Modules valid only for that ABI |
| Reuse `.ko` across `-31` → `-38` | **Forbidden** — rebuild |

After every `linux-image` upgrade:

1. Keep previous ABI bootable (GRUB gate — `snd-repair gate`).
2. Install matching `linux-headers` + `linux-source`.
3. `snd-repair build` → `install-modules` → reboot → `status` + smoke ([VALIDATION.md](../VALIDATION.md)).
4. Do not purge the old image for 1–2 days.

Runtime `snd reset` cannot fix a **missing overlay** on a new ABI.

---

## 6. Git workflow

| Branch | Role |
|--------|------|
| `main` | Product install path (default for clones and PRs) |
| `resolution/bruteforce` | Optional local checkout of lab archive (also tagged `archive/resolution-bruteforce`) |
| `research/…` | Short-lived experiments; promote notes to `main`, then delete branch |
| `fix/…` / `fix/…` | Short-lived; delete after merge |

**Commits**

- English messages; focus on **why**.
- Update `CHANGELOG.md` under `## Unreleased` with the change.
- Do not commit: `build/linux-source/`, staging `.ko` / `.ko.zst`, secrets, local WirePlumber state.

**Pull requests**

- Summary: symptom, layer (A/B/C vs 000x), ABI tested (`uname -r`).
- Test plan: cold boot `speaker-test`, one s2idle cycle, `snd-repair status` markers, mic default ≠ sink/HDMI monitor.
- Link `research/**/INCIDENT-*` when fixing a logged failure class.

---

## 7. Versioning and tags

| Object | Identifier |
|--------|------------|
| Product source | Git commit on `main` (+ optional tag) |
| Installed fix | Overlay for **one** kernel ABI + `/var/lib/snd_repair/` state |
| Patch series | Markers `0001`, `0001b`, `0002`, `0003`, `0003b` |

### Tagging (after smoke on the target ABI)

```bash
git tag -a overlay-7.0.0-38 -m "Overlay validated on 7.0.0-38-generic (PX13)"
git tag -a v0.3.0 -m "Product release: …"   # optional SemVer for docs/CLI
git push origin overlay-7.0.0-38 v0.3.0
```

| Tag form | Use |
|----------|-----|
| `overlay-<kver>` | This commit builds cleanly for that ABI |
| `vMAJOR.MINOR.PATCH` | User-facing product / docs / CLI changes |

Do **not** tag every WIP commit. Tag only after `status` live OK + [VALIDATION.md](../VALIDATION.md) smoke.

### Changelog

1. All user-visible or rebuild-affecting work goes under `## Unreleased` first.
2. On tag `vX.Y.Z`, rename to `## [X.Y.Z] — YYYY-MM-DD` and open a fresh `## Unreleased`.
3. Note **ABI tested** and any patch refresh forced by kernel source drift.
4. Keep deep investigation in `research/`; changelog stays short bullets.

---

## 8. Validation gate (before merge / tag)

```bash
./scripts/snd-repair status
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
systemctl suspend   # wake, then again
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
wpctl status        # Source ≠ Speaker sink / HDMI monitor
```

Fail the gate if: Dummy Output only, FW `-110` storm, slaves UNATTACHED, or markers missing after reboot.

---

## 9. Incidents and research

1. Collect runtime evidence (dmesg/journal/`wpctl`, or project snapshot scripts).
2. Write `research/<track>/INCIDENT-YYYYMMDD-….md` in **English**.
3. Separate stacked failures (Scenario 2 mute vs WirePlumber Source=sink vs missing overlay).
4. Promote a durable recovery into `docs/troubleshooting.md` + scripts only after evidence.

---

## 10. Checklists

### Changed a kernel patch

- [ ] `reset-kernel-tree` + `apply-upstream-patches` exit 0
- [ ] `snd-repair build` stages three `.ko.zst` with markers
- [ ] `install-modules` + reboot; `status` → live OK
- [ ] VALIDATION smoke (cold + one S2)
- [ ] `CHANGELOG.md` Unreleased bullet
- [ ] `PATCHES.md` updated if semantics/markers changed
- [ ] Commit / PR on `main`; tag only if cutting a release
- [ ] Previous ABI still bootable until soak passes

### Kernel upgraded under you

- [ ] `snd status` → live MISSING / overlay absent for new `uname -r`
- [ ] Headers + source installed for new ABI
- [ ] If apply fails → refresh patch (§3), do not force
- [ ] build → install-modules → reboot → status + smoke
- [ ] Changelog note: rebuild required for that ABI
