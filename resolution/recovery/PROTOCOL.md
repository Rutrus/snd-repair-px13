# Binary recovery protocol

English (canonical). **Edge framework** — see [../EDGE-FRAMEWORK.md](../EDGE-FRAMEWORK.md).

---

## Closure ladder (not one PASS)

```text
Hypothesis → PASS×1 → Reproducible 5/5 → Stable Edge → research/
```

Only **Stable Edge** (5/5 full Recovery Signature) re-opens research.

---

## Recovery Signature

| Check | Partial (PASS×1) | Full (counts toward 5/5) |
|-------|------------------|---------------------------|
| S1 RT721 / SDW attach | ✓ | ✓ |
| S2 ALSA card | ✓ | ✓ |
| S3 userspace sink | ✓ | ✓ |
| S4 speaker-test | ✓ | ✓ |
| S5 suspend #2 → still S4 | — | ✓ |

---

## Standard run

```bash
# Full cycle (S0 → suspend → S2 → recovery → signature)
sudo EDGE_FULL_SIGNATURE=1 ./resolution/scripts/edge-cycle.sh E09

# Recovery only (already in S2)
sudo EDGE_FULL_SIGNATURE=1 ./resolution/scripts/recovery/run-recovery.sh R09
```

Framework prints structured report + **Next Candidate**.

---

## Strict order

1. **E09** until Stable (5/5) or saturated (3× zero-K)
2. **E07** — same discipline
3. **E08** → **E04** → **firmware/**

Do **not** switch edges after one PASS — repeat to 5/5.

---

## Information saturation

3 consecutive FAIL with zero Knowledge Gain → branch **saturated** → next edge in `state.json`.

No more runs on saturated branch. No new instrumentation.

---

## After Stable Edge

1. Update [../edges/INDEX.md](../edges/INDEX.md)
2. Re-open research with **one** question from edge definition
3. See [../UPSTREAM-VALUE.md](../UPSTREAM-VALUE.md)

---

## Related

| Doc | Role |
|-----|------|
| [../edges/E09.md](../edges/E09.md) | Active edge |
| [../edges/state.json](../edges/state.json) | Confidence machine state |
| [../TRACKER.md](../TRACKER.md) | Human log |
