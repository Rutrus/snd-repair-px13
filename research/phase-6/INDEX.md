# Phase 6 — State transition analysis (suspend → resume)

> **Branch:** `research/suspend-lifecycle`  
> **Status doc:** [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md) ← **canonical snapshot** (~80–85% delimited)  
> **Rule:** No behavior-changing kernel patches until post-reset AMD IRQ chain bisect is complete.  
> **Next:** Minimal AMD trace — [proposed/NEXT-AMD-IRQ-TRACE.md](proposed/NEXT-AMD-IRQ-TRACE.md).

English (canonical). Phase 5 delivered playback/FW/stereo. Phase 6 explains **intermittent s2idle resume** on ACP70 SoundWire.

---

## Current finding

After `manager_reset`, FAIL runs show **no log evidence** of PING/work/handle/ATTACHED. The gap is **after** `amd_resume_runtime()`. Binary question: does the first IRQ/ping post-reset run?

Two FAIL classes:

| Class | RT721 path | Runs |
|-------|------------|------|
| **FAIL-1** | `wait_init` → timeout `-110` | 0004–0006 |
| **FAIL-2** | `resume_early_exit` (no wait) | 0007 |

```bash
./scripts/phase6-experiment.sh sm 0005   # FAIL-1
./scripts/phase6-experiment.sh sm 0007   # FAIL-2
```

---

## Documents

| Doc | Content |
|-----|---------|
| [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md) | Runs, H1–H4, gap diagram, IO_PAGE_FAULT notes, exit criteria |
| [SOUNDWIRE-RESUME-STATE-MACHINE.md](SOUNDWIRE-RESUME-STATE-MACHINE.md) | State diagram, Case A–D |
| [LINK-REENUMERATION-FAILURE.md](LINK-REENUMERATION-FAILURE.md) | Upstream wording |
| [SDW-INITIALIZATION-COMPLETE-MAP.md](SDW-INITIALIZATION-COMPLETE-MAP.md) | wait/complete map |
| [AMD-RESUME-PATHS.md](AMD-RESUME-PATHS.md) | Static call graph |
| [HYPOTHESES.md](HYPOTHESES.md) | Legacy H1–H4 (see status doc for revised IRQ hypotheses) |

---

## Tooling

| Script | Role |
|--------|------|
| [`scripts/phase6-experiment.sh`](../../scripts/phase6-experiment.sh) | `arm` · `disarm` · `arm --force` · `sm` · `tl` · `matrix` · `status` |
| [`scripts/phase6-state-machine.sh`](../../scripts/phase6-state-machine.sh) | State sequence + **Resume path** block |
| [`scripts/phase6-resume-timeline.sh`](../../scripts/phase6-resume-timeline.sh) | Δt timeline (kernel clock for waits) |
| [`scripts/build-phase6-amd-trace.sh`](../../scripts/build-phase6-amd-trace.sh) | AMD PHASE6 0003+0004 (IRQ chain + snd-pci-ps) |
| [`scripts/build-phase6-sdw-trace.sh`](../../scripts/build-phase6-sdw-trace.sh) | Bus PHASE6 trace |
| [`scripts/build-phase6-rt721-trace.sh`](../../scripts/build-phase6-rt721-trace.sh) | RT721 PHASE6 trace |

---

## Artifacts

| Path | Content |
|------|---------|
| `validation/phase6-runs/run-NNNN/` | Per-run dumps + `kmsg-phase6-window.log` |
| `validation/phase6-chronology.csv` | Userspace samples |
| `validation/resume-matrix.csv` | Composite row per run |

---

## Relation to Phase 5

Phase 5 patches (TAS2783 FW, etc.) **frozen** until re-enumeration path is understood. RT721/TAS2783 are witnesses only.

Prior: [`../phase-5/BIFURCATION-EXPERIMENT.md`](../phase-5/BIFURCATION-EXPERIMENT.md)

---

## Exit criteria

See [PHASE-6-INVESTIGATION-STATUS.md#exit-criteria-updated](PHASE-6-INVESTIGATION-STATUS.md#exit-criteria-updated).
