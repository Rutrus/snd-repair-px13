# Phase 7 — Bring-up experiments (ACP70)

> **Branch:** `research/suspend-lifecycle` (or `research/phase7-bringup` when split)  
> **Plan:** [BRINGUP-EXPERIMENTS.md](BRINGUP-EXPERIMENTS.md)  
> **Phase 6 (closed):** [../phase-6/INDEX.md](../phase-6/INDEX.md)

English (canonical). Phase 6 **observation** is complete. Phase 7 **delimitation** is complete — **frozen** as of correlate d50.

> **Upstream:** [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) · **Next:** Phase 8 (ACP platform IRQ restore)

---

## Status: frozen

All Phase 7 experiments closed. Do not add new bring-up experiments unless correlate boundary is contradicted.

| Milestone | Doc |
|-----------|-----|
| Delivery boundary | [0007-run-correlate-d50.md](experiments/0007-run-correlate-d50.md) |
| Downstream sufficiency | [0006a-run-p7-d50.md](experiments/0006a-run-p7-d50.md) |
| Upstream narrative | [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) |

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
| **0007** IRQ delivery trace | [experiments/0007-irq-delivery-trace.md](experiments/0007-irq-delivery-trace.md) | **Closed** — [boot run](experiments/0007-run-resume-no-handler.md) + [correlate d50](experiments/0007-run-correlate-d50.md) |
| **0006c** force stat 0x4 | [experiments/0006c-force-schedule-stat4.md](experiments/0006c-force-schedule-stat4.md) | **Obsolete** (0006a positive) |

---

## Archived protocols

```bash
./scripts/build-phase7.sh --experiment irq-stat-correlate --delay 50
./scripts/phase7-irq-snapshot.sh pre-suspend
./scripts/phase7-sweep-pre.sh 50
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes p7-correlate-d50
systemctl suspend
./scripts/phase7-irq-snapshot.sh post-resume
./scripts/phase6-hunt.sh post-suspend --save-window
journalctl -k -b 0 | grep -E 'PHASE7 ctx=(acp|amd) fn='
```

---

## Run protocol (0007 boot-only, archived)

```bash
./scripts/build-phase7.sh --experiment irq-delivery-trace
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes p7-0007-boot
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
journalctl -k -b 0 | grep 'PHASE7 ctx=acp fn='
```

---

## Run protocol (0006a, archived)

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
| [experiments/0007-irq-delivery-trace.md](experiments/0007-irq-delivery-trace.md) | PCI IRQ path + correlate protocol |
| [experiments/0007-run-resume-no-handler.md](experiments/0007-run-resume-no-handler.md) | Run p7-0007-boot (delivery FAIL) |
| [experiments/0007-run-correlate-d50.md](experiments/0007-run-correlate-d50.md) | Run p7-correlate-d50 (boundary closed) |
