# R003 — Kernel behaviour mutations

English (canonical). Track **C**.

**Goal:** change driver behaviour — not observe it. One mutation per build unless track H combo.

**Status:** `?`

---

## Mutation catalog

| Id | Mutation | File(s) | Risk |
|----|----------|---------|------|
| C1 | Never call `acp70_disable_interrupts()` on suspend | `ps-common.c` | IRQ left enabled — may affect suspend power |
| C2 | Skip ACP block reset on resume | `ps-common.c` | |
| C6 | `device_set_wakeup_enable(false)` | `pci-ps.c` | |
| C7 | Swap ordering: enable IRQ before manager_reset | `amd_manager.c` | |

Add patches under `resolution/experiments/proposed/` when created.

---

## Build discipline

```bash
# Future: resolution/scripts/build-resolution.sh --mutation C5
./scripts/build-from-upstream.sh   # baseline rollback
```

---

## Already falsified (research — do not repeat as “new”)

| Change | Result |
|--------|--------|
| STAT1 preclear (patch A) | FAIL |
| Delay after D0 only (0005) | FAIL |
| Manual schedule_work (0006a) | PASS (sufficiency) |

---

## Result

| Id | Build | Result | Notes |
|----|-------|--------|-------|
| — | — | — | |
