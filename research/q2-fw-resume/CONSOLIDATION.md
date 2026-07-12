# Q2 consolidation — investigation handoff (2026-07-12)

English (canonical). **State-based investigation** — symptom layers closed; **Q3** opens.

**Q2 witness:** [../experiments/q2-fw-trace-witness-20260712.md](../experiments/q2-fw-trace-witness-20260712.md)  
**Q3 (active P0):** [../q2.5-sdw-reattach/README.md](../q2.5-sdw-reattach/README.md)

---

## Question tree

```text
Q1   hw_params → -EINVAL                 [~100% closed]
Q2   FW never started                     [~90–95% closed this cycle]
Q2.5 io_init never ran (not ATTACHED)     [closed this cycle]
Q3   first missing SDW re-attach step     [OPEN]
```

Two questions that were previously mixed are now separate:

| Old mix | Now |
|---------|-----|
| Why does hw_params fail? | Q1 + Q2 |
| Why does resume fail? | Q3 |

---

## Demonstrated this cycle (do not over-claim)

```text
resume → status != ATTACHED → skip_io_init → no nowait
    → fw_dl_task_done false → wait timeout → -EINVAL
```

**Bounded:** failure is **before** `tas_update_status()` would run `io_init()` on ATTACHED.

**Not demonstrated:** first break in `PM resume → manager → enumeration → ATTACHED`. Do **not** assume `manager_reset`.

---

## Correlated observation (same boot)

`initialization timed out (-110)` **and** `master_port OK` / port programming OK.

**Inference:** master can program the bus; **slave init protocol** does not complete — not necessarily a dead link.

---

## Series B (0003)

Requires ATTACHED. This cycle: `UNATTACHED` → 0003 never entered. Not wrong; precondition fails here.

---

## Maturity

| Layer | Estimate |
|-------|----------|
| Q1 | ~100% |
| Q2 | ~90–95% |
| Q2.5 (layer) | closed this cycle |
| Q3 | active |

---

## Wording for upstream

**Use:** “First missing SoundWire re-attach transition after resume (Q3).”

**Avoid:** “Bug in manager_reset”; “TAS2783 FW bug” as primary frame.
