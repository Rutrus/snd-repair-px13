# Phase 6 — State transition analysis (suspend → resume)

> **Branch:** `research/suspend-lifecycle` (or `research/state-transitions`)  
> **Started:** 2026-07-10  
> **Rule:** **No kernel driver patches** until PASS/FAIL bifurcation is explained.

English (canonical). Phase 5 traced TAS2783 lifecycle; Phase 6 shifts to **horizontal** analysis: two stable outcomes after resume, one diverging transition.

---

## Two stable states

```
Resume
   │
   ├── PASS branch          └── FAIL branch
       rt721 OK                 rt721 timeout → PM -110
       Attached                 Unattached (stuck)
       FW reload                No FW path
       Speaker (wpctl)          Dummy Output
       Audio                    No audio
```

**Question:** not *which patch?* but *which event selects PASS vs FAIL?*

---

## Objective

Find the **first temporal divergence** between a good and bad resume — millisecond-relative chronology from `PM: suspend exit`.

---

## Hypotheses (Phase 6)

| ID | Statement | Test |
|----|-----------|------|
| **H1** | RT721 resume never completes → everything downstream fails | RT721 chronology + first `-110` offset_ms |
| **H2** | SDW master leaves bus in state where slaves never re-ATTACH | sysfs `status` timeline; post-PCI attach retry? |
| **H3** | Race: PM resume vs PipeWire stream vs FW reload | Compare pw stream open offset vs attach/fw |
| **H4** | ACP70 timing window — fail only at certain resume latency | load1, suspend depth, offset variance across N runs |

Details: [HYPOTHESES.md](HYPOTHESES.md)

---

## Method

1. **Freeze kernel code** (TAS2783 / 0003 on hold).
2. **High-resolution capture** on healthy boot (#41+): userspace + sysfs every 0–60s.
3. **Kernel event chronology** — parse kmsg with `offset_ms` from resume (no new `dev_err` yet).
4. **Repeat** until one PASS and one FAIL run with identical schema.
5. **`phase6-chronology-diff`** — first differing transition.
6. **Then** decide patch target: RT721, SoundWire core, AMD ACP, PM framework, or TAS2783.

Full protocol: [STATE-TRANSITION-ANALYSIS.md](STATE-TRANSITION-ANALYSIS.md)

---

## Tooling

| Script | Role |
|--------|------|
| [`scripts/phase6-experiment.sh`](../../scripts/phase6-experiment.sh) | `baseline` · `arm` · `status` · `diff` |
| [`scripts/phase6-chronology-capture.sh`](../../scripts/phase6-chronology-capture.sh) | Samples 0, 0.5, 1, 2, 3, 5, 10, 20, 30, 60s + kmsg parse |
| [`scripts/phase6-chronology-diff.sh`](../../scripts/phase6-chronology-diff.sh) | First divergence between two runs |
| [`scripts/phase6-trace-probe.sh`](../../scripts/phase6-trace-probe.sh) | tracefs / dynamic_debug availability (read-only) |
| [`scripts/lib/validation-metrics.sh`](../../scripts/lib/validation-metrics.sh) | Composite PASS metrics |

---

## Artifacts

| Path | Content |
|------|---------|
| `validation/phase6-chronology.csv` | Userspace/sysfs samples (`offset_s`, attach, fw, wpctl, …) |
| `validation/phase6-kmsg-events.csv` | Kernel events with `offset_ms` |
| `validation/phase6-state-graph.csv` | State nodes + transitions + evidence |
| `validation/resume-matrix.csv` | One composite row per run (PASS/WARN) |
| `validation/phase6-runs/run-NNNN/` | Verbose dumps per offset |

---

## Relation to Phase 5

| Phase 5 | Phase 6 |
|---------|---------|
| TAS2783 `hw_init` / FW reload (0003) | **Frozen** — recovery only works if Attached |
| Bifurcation question identified | **Primary** — measure and diff |
| PHASE5 trace in driver | Keep for parse; **no new trace patches** until diff |

Prior work: [`../phase-5/BIFURCATION-EXPERIMENT.md`](../phase-5/BIFURCATION-EXPERIMENT.md)

---

## Exit criteria (before any kernel patch)

- [ ] ≥1 PASS and ≥1 FAIL run, full chronology
- [ ] First diverging event documented with `offset_ms`
- [ ] State graph updated with evidence lines
- [ ] Patch target layer chosen (RT721 / SDW / ACP / PM / TAS2783)
