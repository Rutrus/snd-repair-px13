# Project state — ASUS ProArt PX13 (July 2026)

> **English (canonical)** | [Español](es/ESTADO-PROYECTO.md)

This document describes **where the project stands now**, not the initial “no audio at all” phase.

**Machine:** ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`  
**Validation matrix:** `validation/fw-matrix.csv` (20 rows as of 2026-07-09)

---

## Global picture

The project has moved through four clear phases:

1. **Restore basic audio** — brainchillz (firmware, UCM, rt721, systemd).
2. **Remove structural kernel faults** — Problems A/B/C (patches 0004, 0006/0007, 0009).
3. **Validate the pipeline** — instrumentation proved AMD → SoundWire → both TAS2783 → stereo on cold boot.
4. **Isolate the last blocker** — **suspend/resume only**; cold boot is no longer the problem.

From a kernel-debugging perspective: the search space collapsed from “no usable audio” to **one reproducible PM resume path** affecting UID `:8` (left SmartAmp).

---

## Resolved

### Basic audio path

Initially: no Speaker device, `-22`, SmartAmp failures, no usable playback.

Now after stage 1 + kernel patches:

- SoundWire enumeration correct
- TAS2783 amps initialize
- AMD → SoundWire → TAS2783 pipeline works
- **Stereo works after cold boot** (manual L/R validation, boot #1)

### Problem A — capture `-EINVAL` (patch 0004)

```
capture → port 2 → sdw_get_slave_dpn_prop() → NULL → -EINVAL
```

TAS2783 advertises `sink_ports` only, not `source_ports`. Patch 0004 skips adding TAS2783 to capture streams.

**Result:** capture `-22` regression eliminated (`REGRESSION_CAPTURE=NO` in all 20 matrix rows).

### Problem C — left channel only (patch 0009)

Instrumentation disproved H2 (“second TAS never joins stream”). Both UIDs showed trigger/prepare/hw_params.

Root cause: wrong `ch_mask` — both amps got `0x3` instead of `0x1` / `0x2`.

**Result:** `speaker-test -s 1` → left only; `-s 2` → right only. Stereo OK.

### Firmware on cold boot (patches 0006 + 0007)

Intermittent `FW download failed -110` and `playback without fw` on early boots.

After 0006/0007: representative boots with `:8 OK`, `:b OK`, enabling stereo work to proceed without conflating FW with routing.

---

## Ruled out (with evidence)

No longer under investigation:

- AMD / ACP70 / `soundwire-amd` broken
- ACPI matching, DisCo, transport_params
- SoundWire enumeration
- PipeWire / WirePlumber as root cause (can aggravate resume timing, not origin of `-110`)
- SmartAmp hardware fault
- ch_map, capture path, UCM (for the remaining blocker)

---

## The only serious remaining issue

### Suspend / resume

After `systemctl suspend` (or lid close):

```
PM resume → -110 → :8 done=0 → Dummy Output
```

While `:b` usually survives.

**Pattern:**

| Action | Outcome |
|--------|---------|
| Cold reboot | Speaker OK |
| Suspend → resume | Often broken until reboot |

### Matrix (corrected)

| Context | Metric | Value |
|---------|--------|-------|
| **Cold boot** | `:b` FW | **20/20 OK** |
| **Cold boot** | Both UIDs OK (global) | **9/10** boot rows (boot #2 WARN) |
| **Cold boot** | Stereo L+R (manual `--audio`) | **1/1 OK** |
| **Suspend/resume** | Both UIDs OK (real tests) | **0/9** (row #16 = false positive, no suspend) |

The problem is **not cold boot**. It is exclusively the **resume path**.

---

## Current hypothesis

One primary hypothesis remains:

**H1 — PM resume:** The SoundWire / TAS2783 driver does not correctly restore the **left** SmartAmp (UID `:8`) on PM resume. Not at boot, not at probe — only after s2idle resume.

Asymmetry (`:b` stable, `:8` fails) fits left amp / `1714-1-8.bin` being more fragile on warm resume.

---

## Current priority

**Active work:** Phase 7 bring-up on ACP70 SoundWire resume. See **[research/JOURNEY.md](../research/JOURNEY.md)**.

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-phase7.sh --experiment stat-decode   # 0006b (observation)
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes p7-0006b
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
```

If Phase 6/7 patches fail to apply: `./scripts/regenerate-phase6-amd-patches.sh`

**Resolution target:** ≥6/6 real suspend/resume OK in `validation/fw-matrix.csv` without reboot.

---

## References

| Topic | Location |
|-------|----------|
| Install (stage 1 + 2) | [INSTALL.md](INSTALL.md) |
| FW validation | [FW-VALIDATION.md](FW-VALIDATION.md) |
| Failure tracks (historical) | [../research/FAILURE-REPORT-2026-07-09.md](../research/FAILURE-REPORT-2026-07-09.md) |
| Active debug checklist | [../research/PRIORITY-DEBUG.md](../research/PRIORITY-DEBUG.md) |
| Sudo commands | [../research/SUDO-RUNBOOK.md](../research/SUDO-RUNBOOK.md) |
