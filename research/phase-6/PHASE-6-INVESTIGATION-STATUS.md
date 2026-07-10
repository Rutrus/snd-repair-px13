# Phase 6 investigation status (ACP70 / PX13)

English (canonical). Last updated: 2026-07-10 (run **0013**).

**Delimitation:** ~**95%** — *where* the sequence breaks is identified; ~**5%** remains (*why* STAT=0 on FAIL + PASS contrast).

**Facts:** [KNOWN-FACTS.md](KNOWN-FACTS.md) · **0006 plan:** [proposed/NEXT-ACP-STAT-ZERO.md](proposed/NEXT-ACP-STAT-ZERO.md)

---

## Objective shift (not a percentage game)

| Stage | First unknown |
|-------|----------------|
| Early Phase 6 | `manager_reset` → **?** → timeout |
| **Now (0013)** | `irq_enabled` → **`STAT=0`** → no IRQ |

The project no longer searches *where* it fails. It explains **why the first expected hardware-visible state does not appear** after `manager_reset` + `irq_enabled`.

---

## Observable break (run 0013)

```text
manager_reset → irq_enabled → ACP_EXTERNAL_INTR_STAT=0 → (no handler) → no completion → -110
```

**Maintainer-safe fact:** on the instrumented read immediately after `irq_enabled`, STAT is 0 and no IRQ handler activity occurs during the wait window. **Not** equivalent to proving HW never fires.

---

## PASS contrast (gold)

| | FAIL | PASS |
|--|------|------|
| `irq_enabled` | ✓ | ✓ |
| STAT | 0 | ≠0 |
| handler | ✗ | ✓ |
| completion | ✗ | ✓ |
| RT721 | -110 | OK |

Same instrumentation (0003–0005; 0006 optional). More convincing than extra log volume.

---

## Next: 0006 (ACP block state only)

Structured snapshot after enable — CNTL, STAT, SDW enable, optional clock/frame — answering *is the block prepared to generate the first event?*

**Frozen:** RT721, TAS2783, bus.c, userspace, PipeWire, px13 rebind.

---

## Runs

| Run | Note |
|-----|------|
| 0010, 0012 | Gap after `irq_enabled` |
| **0013** | STAT=0, S2 ruled out |

```bash
./scripts/phase6-experiment.sh sm 0013
```

---

## Exit criteria

- [x] First **observable** break identified (STAT=0, 0013)
- [x] S2 ruled out on 0013
- [ ] 0006 block-state snapshot on FAIL (+ PASS compare)
- [ ] Clean-boot PASS with 0003–0005

---

## Commands

```bash
./scripts/build-phase6-amd-trace.sh
./scripts/phase6-experiment.sh sm 0013
```
