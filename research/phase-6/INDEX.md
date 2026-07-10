# Phase 6 — State transition analysis (suspend → resume)

> **Branch:** `research/suspend-lifecycle`  
> **Facts:** [KNOWN-FACTS.md](KNOWN-FACTS.md)  
> **Status:** [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md) — delimitation complete (0015); **PASS hunt / upstream submit**  
> **Upstream:** [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md) · [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md)

English (canonical). Phase 5 delivered playback/FW/stereo. Phase 6 documents **intermittent s2idle resume** on ACP70 SoundWire.

---

## Current finding (run 0015)

Software `POWER_OFF` resume sequence **complete** on FAIL; block **programmed**; **`STAT=0`** and **no handler** in wait window. RT721 `-110` is downstream.

```bash
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-reboot --notes run-NN
systemctl suspend
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-suspend
```

Or: `./scripts/phase6-experiment.sh sm` for last resume window only.

**Do not add horizontal trace.** Capture PASS with same 0003–0007.

---

## Documents

| Doc | Content |
|-----|---------|
| [KNOWN-FACTS.md](KNOWN-FACTS.md) | Demonstrated vs not demonstrated |
| [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md) | **Submit-ready** — Observed / Not demonstrated / golden diff |
| [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md) | Golden diff table + submit checklist |
| [UPSTREAM-STRATEGY.md](UPSTREAM-STRATEGY.md) | No-PASS strategy, deterministic FAIL, userspace contrast |
| [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md) | Runs, exit criteria |
| [proposed/0006-phase6-acp-block-state.patch](proposed/0006-phase6-acp-block-state.patch) | ACP register snapshot (0006) |
| [proposed/0007-phase6-resume-kick-trace.patch](proposed/0007-phase6-resume-kick-trace.patch) | Resume kick sequence trace (0007) |
| [SOUNDWIRE-RESUME-STATE-MACHINE.md](SOUNDWIRE-RESUME-STATE-MACHINE.md) | State diagram |
| [AMD-RESUME-PATHS.md](AMD-RESUME-PATHS.md) | Static call graph |

---

## Tooling

| Script | Role |
|--------|------|
| [`scripts/phase6-hunt.sh`](../../scripts/phase6-hunt.sh) | **post-reboot / post-suspend** PASS hunt workflow |
| [`scripts/phase6-experiment.sh`](../../scripts/phase6-experiment.sh) | `arm` · `sm` · `status` |
| [`scripts/phase6-state-machine.sh`](../../scripts/phase6-state-machine.sh) | State sequence + Resume path block |
| [`scripts/build-phase6-amd-trace.sh`](../../scripts/build-phase6-amd-trace.sh) | AMD 0003–0007 (keep for PASS) |

Bus/RT721 build scripts — **frozen** for root-cause work.

---

## Exit criteria

See [PHASE-6-INVESTIGATION-STATUS.md](PHASE-6-INVESTIGATION-STATUS.md). Remaining: **PASS run** or scenario-3 submit.

## Artifacts

| Path | Content |
|------|---------|
| `validation/phase6-runs/run-NNNN/` | Per-run dumps + `kmsg-phase6-window.log` |
| `validation/phase6-hunt-log.csv` | Bounded PASS hunt log (kernel witness per attempt) |
| `validation/phase6-chronology.csv` | Userspace samples |
