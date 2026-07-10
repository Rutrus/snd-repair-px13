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
| **0006b** STAT decode | [experiments/0006b-stat-decode.md](experiments/0006b-stat-decode.md) | **Next (commit 1)** — observation only; CNTL/STAT decode |
| **0006a** validate manager mask | [experiments/0006a-validate-manager-mask.md](experiments/0006a-validate-manager-mask.md) | **After 0006b (commit 2)** — `stat & manager_mask` → `schedule_work` |
| **0006c** force stat 0x4 | [experiments/0006c-force-schedule-stat4.md](experiments/0006c-force-schedule-stat4.md) | Optional falsification after 0006a/b |

---

## Current question (post-0005)

> A bit appears in `ACP_EXTERNAL_INTR_STAT(instance)` after delay (`0x4`), but `acp63_irq_handler` waits for `ACP_SDW0_STAT` (`0x200000`). **Does the driver-expected manager mask bit ever assert? If so, does manual `schedule_work` progress enumeration?**

---

## Run protocol (0006a, when patch exists)

```bash
./scripts/build-phase7.sh --experiment validate-manager-mask   # TBD
sudo reboot
./scripts/phase7-sweep-pre.sh 50
# login:
./scripts/phase7-sweep-post.sh --verify-only
./scripts/phase7-sweep-post.sh
systemctl suspend
./scripts/phase7-sweep-post.sh --after-suspend
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
