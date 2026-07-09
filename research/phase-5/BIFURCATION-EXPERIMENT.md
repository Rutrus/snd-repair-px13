# Bifurcation experiment — ATTACHED vs UNATTACHED after PM -110

> **Superseded for capture protocol by Phase 6:** [`../phase-6/STATE-TRANSITION-ANALYSIS.md`](../phase-6/STATE-TRANSITION-ANALYSIS.md)  
> Use [`scripts/phase6-experiment.sh`](../../scripts/phase6-experiment.sh) for high-resolution chronology.

## Core question

After `PM failed to resume: error -110`, what determines whether SoundWire slaves return to **`Attached`** (boots #30–38 kmsg) or stay **`Unattached`** (boot #40, user-visible failure)?

Recovery mechanisms (patch 0003, PCI reset, PipeWire restart) only matter **after** attach succeeds. Until the bifurcation is understood, **do not patch the TAS2783 driver**.

## Revised hypothesis

> The real failure is **SoundWire link state restoration after resume**, not missing FW reload. FW reload only runs when slaves are `Attached`; when attach never happens, FW never gets a chance.

The first symptom in kmsg is consistently **rt721** init timeout → `-110`, before TAS2783 errors. RT721 may be the **ordering blocker**, not the amplifier FW path.

## PASS criteria (composite)

```
PASS = pm_ok
    AND uid8_attach == YES
    AND uid8_fw == YES
    AND speaker_present == YES   (wpctl, not Dummy)
    AND speaker_test == YES

Everything else → WARN (even if dmesg is clean)
```

Legacy `fw-matrix.csv` `uid8_fw=OK` alone is **insufficient** — documented false positives on boots #30–#38 (0× playback errors in kmsg but PipeWire failures in timeline; early collect before px13 finished).

## Instrumented experiment (Boot #41+)

On a healthy boot (`:8` Attached, `fw_ok=1`):

```bash
./scripts/phase5-bifurcation-experiment.sh baseline --notes boot41-pre
./scripts/phase5-bifurcation-experiment.sh arm --notes boot41-run1
systemctl suspend
# after wake: automatic samples at t=0,2,5,10,20,30,60s
./scripts/phase5-bifurcation-experiment.sh status
```

Each sample records:

| Layer | Metric |
|-------|--------|
| Userspace | `wpctl status`, `pw-cli ls Node`, `aplay -l`, PipeWire active |
| SDW sysfs | `/sys/bus/soundwire/devices/.../status` (`Attached` / `Unattached`) |
| Kernel | PM `-110`, `playback without fw`, PHASE5 attach/FW flags |
| Runtime PM | `power/runtime_status` per slave |
| Audio | `speaker-test` 1s (non-interactive) |

Outputs:

- `validation/bifurcation-timeline.csv` — one row per (run, offset_s)
- `validation/bifurcation-runs/run-NNNN/t*.txt` — verbose dumps
- `validation/resume-matrix.csv` — one composite row per run

## Resume matrix schema

| Column | Meaning |
|--------|---------|
| `pm` | OK / FAIL (-110 or rt721 timeout since resume) |
| `attach` | `:8` sysfs Attached at t=60s |
| `fw` | `:8` fw_ok (no playback-without-fw since resume) |
| `speaker` | wpctl Speaker vs Dummy |
| `audio` | speaker-test result |
| `composite` | PASS / WARN |
| `post_pci_attach` | After px13 PCI bind: any `update_status_attached :8` in kmsg |

## Known contrast (manual, boot #40)

| Boot | PM | Attach | FW | Speaker | Audio | Composite |
|------|-----|--------|-----|---------|-------|-----------|
| 40 | FAIL | NO | NO | Dummy | NO | WARN |
| 41 (baseline) | OK | YES | YES | TBD | TBD | pending experiment |

## Next analysis (after PASS + FAIL traces)

1. Diff first diverging transition between two full 60s movies.
2. Instrument **rt721** PM path at same granularity as TAS2783 PHASE5 (probe → resume → attach → first xfer → timeout).
3. Answer: **does the framework retry bus enumeration after PCI reset if slaves stay Unattached?** (boot #40 suggests NO).

## Related files

- [`../SUSPEND-EVAL-2026-07-09-2240.md`](../SUSPEND-EVAL-2026-07-09-2240.md) — cable icon, px13 false positive
- [`tracks/T05-resume-ordering.md`](tracks/T05-resume-ordering.md) — ordering spine
- [`scripts/phase5-bifurcation-experiment.sh`](../../scripts/phase5-bifurcation-experiment.sh)
