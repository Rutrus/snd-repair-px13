# Phase 7 — Bring-up experiments (ACP70)

> **Branch:** `research/suspend-lifecycle` (or `research/phase7-bringup` when split)  
> **Plan:** [BRINGUP-EXPERIMENTS.md](BRINGUP-EXPERIMENTS.md)  
> **Phase 6 (closed):** [../phase-6/INDEX.md](../phase-6/INDEX.md)

English (canonical). Phase 6 **observation** is complete. Phase 7 asks: **what change makes the first HW event appear?**

---

## Mode shift

| | Phase 6 | Phase 7 |
|--|---------|---------|
| Method | `printk` / register read | **Controlled intervention** |
| Goal | Delimit break | **First behaviour change** |
| Another identical FAIL | Useful (N/N) | **Low value** |

---

## Experiment status

| Id | Doc | Status |
|----|-----|--------|
| **0005** delay-after-D0 | [experiments/0005-delay-after-d0.md](experiments/0005-delay-after-d0.md) | **Closed (negative)** — STAT 0→4, no handler; not `ACP_SDW0_STAT` |
| **0006b** STAT decode | [experiments/0006b-stat-decode.md](experiments/0006b-stat-decode.md) | **Closed** — Case 1 (STAT&mask @ +50 ms, no handler) |
| **0006a** validate manager mask | [experiments/0006a-validate-manager-mask.md](experiments/0006a-validate-manager-mask.md) | **Closed (A)** — [run p7-d50](experiments/0006a-run-p7-d50.md): manual schedule → PASS path |
| **0006c** force stat 0x4 | [experiments/0006c-force-schedule-stat4.md](experiments/0006c-force-schedule-stat4.md) | Optional falsification after 0006a/b |

---

## Current question (post-0006a)

> **IRQ delivery:** `STAT(instance)&manager_mask` asserts at +50 ms but `acp63_irq_handler` never runs. Manual `schedule_work` unblocks enumeration ([0006a run](experiments/0006a-run-p7-d50.md)). **Next:** upstream fix in `pci-ps.c` / MSI routing — not manager resume sequence.

---

## Run protocol (0006a)

```bash
./scripts/build-phase7.sh --experiment validate-manager-mask --delay 50
./scripts/phase7-sweep-pre.sh 50
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes p7-0006a-d50
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
```

Same witness as Phase 6 (`resume_n=1`, hunt log, state machine).

When Phase 7 sweep complete:

```bash
./scripts/phase7-sweep-clear.sh && sudo reboot
```

---

## Documents

| Doc | Content |
|-----|---------|
| [BRINGUP-EXPERIMENTS.md](BRINGUP-EXPERIMENTS.md) | Experiments A–D, patch ids, rules |
| [experiments/0005-delay-after-d0.md](experiments/0005-delay-after-d0.md) | Timing falsification (archived) |
| [experiments/0006a-validate-manager-mask.md](experiments/0006a-validate-manager-mask.md) | Manager mask + manual schedule |
| [experiments/0006b-stat-decode.md](experiments/0006b-stat-decode.md) | INTR_STAT/CNTL decode |
| [experiments/0006c-force-schedule-stat4.md](experiments/0006c-force-schedule-stat4.md) | Deliberate 0x4 hack (optional) |
