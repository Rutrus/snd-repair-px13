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

### Suspend / resume — unified model (2026-07-12)

**Canonical doc:** [../research/UNIFIED-CAUSAL-MODEL.md](../research/UNIFIED-CAUSAL-MODEL.md)

**Demonstrated manifestation** after s2idle resume:

```text
PCM0 (RT721)  → hw_params PASS
PCM2 (SmartAmp) → hw_params -EINVAL
→ Dummy Output (consequence, not root cause)
```

Historical logs (`:8 done=0`, `playback without fw download`) are the **same failure class** at an earlier observation altitude — likely `tas_sdw_hw_params()` in stock 7.0.0.

**Pattern:**

| Action | Outcome |
|--------|---------|
| Cold reboot | Speaker OK |
| Suspend → resume | PCM2 EINVAL until reboot |
| PCI remove/rescan / module reload | Reconverges to PCM2 EINVAL |

Cold boot is resolved. The blocker is **resume-only SmartAmp state**, not global PCI/SoundWire death.

---

## Current work (dual track — July 2026)

**KPI:** suspend → resume → **Speaker works** (≥6/6 in `validation/fw-matrix.csv`).

| Track | Status | Entry |
|-------|--------|-------|
| **A — Make it work** | **P0** — try 0006a workaround (W1) | [../research/MAKE-IT-WORK.md](../research/MAKE-IT-WORK.md) |
| **B — Root cause** | C1 closed; upstream packaging | [../research/q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md](../research/q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md) |

**Closed layers:** Q1 (EINVAL site), Q2 (no FW async), Q3 (no ATTACHED), Q3.1 C1 (handler not entered + delta=0).

Question for daily work: **“Which experiment is most likely to restore audio?”** — not only “which hypothesis closes today?”

---

## References

| Topic | Location |
|-------|----------|
| Unified causal model | [../research/UNIFIED-CAUSAL-MODEL.md](../research/UNIFIED-CAUSAL-MODEL.md) |
| Active protocol | [../research/track-PCM-smartamp-hwparams.md](../research/track-PCM-smartamp-hwparams.md) |
| IRQ boundary (frozen) | [../research/frozen/upstream-proof/README.md](../research/frozen/upstream-proof/README.md) |
| Install (stage 1 + 2) | [INSTALL.md](INSTALL.md) |
| FW validation | [FW-VALIDATION.md](FW-VALIDATION.md) |
| Journey | [../research/JOURNEY.md](../research/JOURNEY.md) |
| Sudo commands | [../research/SUDO-RUNBOOK.md](../research/SUDO-RUNBOOK.md) |
