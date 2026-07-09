# Firmware validation matrix — guide

> **English** | [Español](es/VALIDACION-FW.md)

Collect **reproducible boot data** for **Problem B** (intermittent TAS2783 firmware `-110`) and track regressions after kernel patches.

**Goal:** 20–30 cold boots before promoting Series B upstream. See [`../upstream/series-B-firmware/VALIDATION-TODO.md`](../upstream/series-B-firmware/VALIDATION-TODO.md).

---

## What gets recorded

Each boot appends one row to `validation/fw-matrix.csv` and archives a full filtered kernel log under `validation/boot-logs/`.

| Field | Meaning |
|-------|---------|
| `uid8_fw` / `uidb_fw` | Firmware load on left (`0x8`) / right (`0xb`) amp: `OK`, `WARN`, `FAIL110`, `FAIL?` |
| `uid8_warn` / `uidb_warn` | Count of `playback without fw` warnings |
| `regression_capture` | `YES` if Serie A capture/transport regression detected |
| `capture_dailink_warn` | In log header only — known `SDW1-PIN4` prepare `-22` on PX13 |
| `left_audio` / `right_audio` | Only when using `--audio` (manual, interactive) |
| `notes` | Free text, e.g. `auto@boot`, patch set, or `0006+0007+0009` |

Summary statistics: `validation/fw-summary.md` (regenerated on each collect).

---

## Option A — Automatic logging (recommended)

### 1. Install the systemd unit

**User service** (default — no root for install):

```bash
cd ~/snd_repair
./scripts/install-fw-validation-service.sh
```

**System service** (runs at boot without user login):

```bash
sudo ./scripts/install-fw-validation-service.sh --system
```

### 2. Enable linger (user service only)

If you use the **user** unit, it runs when your graphical/TTY session starts. For logging on every reboot **without logging in**:

```bash
sudo loginctl enable-linger "$USER"
```

### 3. What happens on each boot

```
boot → (login or linger) → default.target
     → wait 25s → collect --notes auto@boot
```

### 3b. After each suspend/resume

```
resume → px13-audio-resume (PCI reset ACP)
       → ExecStartPost: fw-validation-suspend-hook.sh (background, non-blocking)
       → ~25s later → collect --suspend --notes auto@suspend
```

Installed as a **drop-in** on `px13-audio-resume.service` (not a parallel `suspend.target` unit — avoids racing the PCI reset).

```bash
sudo ./scripts/install-fw-validation-service.sh --suspend-only
```

### 4. Check that it worked

```bash
systemctl --user status snd-repair-fw-validation.service
systemctl --user status snd-repair-fw-validation-suspend.service
journalctl --user -u snd-repair-fw-validation-suspend.service -b
```

### 5. Uninstall

```bash
./scripts/install-fw-validation-service.sh --remove
```

---

## Option B — Manual logging

After each reboot:

```bash
cd ~/snd_repair
./scripts/fw-validation-run.sh boot
./scripts/fw-validation-run.sh boot --notes "series B RFC test"
```

With interactive stereo check (you answer y/N):

```bash
./scripts/fw-validation-run.sh boot-audio
```

After suspend/resume:

```bash
./scripts/fw-validation-run.sh suspend
```

Sample-rate matrix (no reboot):

```bash
./scripts/fw-validation-run.sh rates
```

Force a second row for the same boot (normally deduplicated):

```bash
./scripts/fw-validation-collect.sh --force --notes "retest"
```

---

## Reading results

### Quick summary

```bash
cat validation/fw-summary.md
```

### Per-boot kernel excerpt

```bash
less validation/boot-logs/boot-003.log
# header lines show uid8_fw, uidb_fw, capture_dailink_warn
```

### Interpret `uid*_fw`

| Value | Meaning |
|-------|---------|
| `OK` | No FW failure or `playback without fw` in dmesg |
| `WARN` | `playback without fw` seen (may still play audio) |
| `FAIL110` | `FW download failed: -110` (Problem B) |
| `FAIL?` | Other negative errno |

---

## Files and scripts

| Path | Role |
|------|------|
| [`../validation/`](../validation/) | CSV, summary, boot logs |
| `scripts/fw-validation-collect.sh` | Core collector |
| `scripts/fw-validation-run.sh` | CLI wrapper (`boot`, `boot-audio`, `suspend`, `rates`, `status`) |
| `scripts/fw-validation-boot-hook.sh` | Delay + collect (called by systemd) |
| `scripts/install-fw-validation-service.sh` | Install/remove unit |
| `systemd/snd-repair-fw-validation.service` | Unit template |

---

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SND_REPAIR_REPO` | repo root | Set by systemd unit |
| `SND_REPAIR_FW_DELAY` | `25` | Seconds to wait after start (FW async load) |
| `VAL_DIR` | `$REPO/validation` | Output directory |
| `ALSA_DEV` | `plughw:1,2` | Device for `--audio` / `rates` |

Example — shorter delay for testing:

```bash
SND_REPAIR_FW_DELAY=10 systemctl --user start snd-repair-fw-validation.service
```

---

## Resume freeze (PX13 + brainchillz)

If the machine **hangs on resume**, check previous boot journal:

```bash
journalctl -b -1 | grep -iE 'px13-audio|soft lockup|unbind failed'
```

Typical sequence (17:26 in testing):

1. `px13-audio-fix: unbind failed/timed out` (PCI `0000:c4:00.5`)
2. Bind attempted anyway
3. `watchdog: soft lockup` on multiple CPUs
4. Hard reboot required

This is the **ACP PCI reset** in brainchillz `px13-audio-resume.service`, not the validation CSV script. Mitigations:

- Close heavy GPU apps before suspend
- Wait for previous `px13-audio-resume` to finish before suspending again (~2 min if PipeWire restart is slow)
- Validation hook now runs **after** px13 completes, in **background** (`nice`/`ionice`)

---

| Layer | Repo | Purpose |
|-------|------|---------|
| Firmware + UCM + suspend | [brainchillz](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) | Stage 1 — speakers visible in PipeWire |
| Kernel patches A/B/C | this repo | Stage 2 — capture, FW retry, stereo L/R |
| **Validation matrix** | `validation/` + this guide | Evidence for Serie B RFC upstream |

Validation does **not** replace [`VERIFICATION.md`](VERIFICATION.md) (post-install sanity check). It builds a **long-term boot database** for statistics.

---

## Troubleshooting

| Symptom | Cause | Action |
|---------|-------|--------|
| No new CSV row after reboot | User unit, no login, no linger | `sudo loginctl enable-linger $USER` or use `--system` |
| Service `inactive (dead)` after boot | Normal until first suspend/resume | Suspend once; then `journalctl -u snd-repair-fw-validation-suspend -b` |
| Suspend unit never runs | Use drop-in on px13 | `sudo ./scripts/install-fw-validation-service.sh --suspend-only` |
| **System freeze on resume** | `px13-audio-fix` PCI unbind timeout + bind | See below — not caused by validation collect |
| Row skipped | Same `boot_id` already logged | Use `--force` for intentional re-run |
| `:8`/`:b` always empty | Wrong machine or no TAS2783 | Confirm PX13; check `journalctl -k -b 0 \| grep tas2783` |
| Permission denied on CSV | Wrong file owner | `chown -R $USER validation/` |

---

## Related docs

- [`../validation/README.md`](../validation/README.md) — directory layout and CSV columns
- [`../upstream/series-B-firmware/VALIDATION-TODO.md`](../upstream/series-B-firmware/VALIDATION-TODO.md) — RFC targets
- [`fw-analysis.md`](fw-analysis.md) — analysis of collected boots
- [`INSTALL.md`](INSTALL.md) — full PX13 install (stages 1 + 2)
