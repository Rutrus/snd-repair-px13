# Witness Quality — S2 oracle before recovery

English (canonical). Separates two questions:

1. **Did we reproduce the broken state (S2)?**
2. **Does the recovery fix it (S2 → S3)?**

Without (1), edge results measure `S? ──R──► S?` and are not conclusive.

---

## Quality levels

| Level | Meaning | Evidence |
|-------|---------|----------|
| **W0** | No suspend | No PM suspend / sleep target in journal window |
| **W1** | Suspend only | Suspend observed; **audio still works** (bug not reproduced) |
| **W2** | S2 certified | Kernel `-110` **or** post-resume **ALSA playback fail** (card present) |
| **W3** | Research S2 signature | W2 **and** `handler_since_pm=0` **and** `STAT1=0x4` |
| **W4** | Full S2 | W3 **and** userspace `dummy`/`none` sink (optional) |

**Dummy Output trap:** After suspend, PipeWire may route to **Dummy Output**. `speaker-test` can **PASS** with zero audible sound. Witness uses **ALSA `plughw` only** when the card is present; dummy default sink ⇒ **S2 broken**.

**Reboot** only when starting a new calibration run from S0, or card missing — not because audio is broken after suspend (that *is* S2).

**VALID** for recovery execution: **≥ W2** (default). **Preferred:** **W3/W4** (requires Phase 7/8 printk in running kernel).

```text
S2 symptom (W2):  suspend → card present → ALSA playback fail
S2 research (W3):  above + handler_since_pm=0 + STAT1=0x4 @ post_delay
```

---

## Edge report semantics

| Witness | Edge result | Meaning |
|---------|-------------|---------|
| **INVALID** | **NOT_EXECUTABLE** | Recovery skipped — initial state unknown |
| **VALID** | PASS / PARTIAL / FAIL | Transition measured from certified S2 |

`PARTIAL 4/4` on **INVALID** witness is **not** evidence for S2→S3.

---

## Priority (framework v2.1)

```text
Reliable S2 (W2+, prefer W3)
        ↓
E04 → E07 → E08 → E09  (re-run with VALID witness)
        ↓
consolidation
```

Exploration queue is **paused** until witness gate passes. Prior E09/E07/E08 runs are marked **ambiguous** (explored without valid witness).

---

## Scripts

| Script | Role |
|--------|------|
| `scripts/s2-reproduce.sh` | Suspend loop — maximize W2/W3 hits |
| `scripts/s2-oracle.sh` | Assess witness after last suspend (no recovery) |
| `scripts/edge-cycle.sh` | S0 → suspend → oracle → recovery **only if VALID** |

Env:

| Var | Default | Role |
|-----|---------|------|
| `RESOLUTION_MIN_WITNESS` | `W2` | Minimum quality to run recovery |
| `PX13_S2_RESUME_WAIT_SEC` | `8` | Wait after resume before witness |

---

## Related

- [STATE-GRAPH.md](STATE-GRAPH.md) — S2 definition
- [EDGE-FRAMEWORK.md](EDGE-FRAMEWORK.md) — exploration rules
- `research/phase-8/` — handler_since_pm, STAT1 evidence
