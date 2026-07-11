# Binary recovery protocol

English (canonical). **Exploration first** — [../EDGE-FRAMEWORK.md](../EDGE-FRAMEWORK.md).

---

## Exploration (default)

One PASS → **next edge**. Do **not** repeat 5×.

```bash
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E09
# PASS → framework says Next: explore E07 (R07)
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E07
```

Queue: **E09 → E07 → E08 → E04 → FW01**

---

## Consolidation sprint (after queue mapped)

When `next-edge.sh` returns `CONSOLIDATION`:

```bash
# state.json phase flips to consolidation automatically on last exploration PASS
sudo EDGE_FULL_SIGNATURE=1 ~/snd_repair/resolution/scripts/edge-cycle.sh E09
# repeat ×3 for best PROMISING edge
```

Requires S5 (suspend #2) on consolidation runs.

---

## PASS / FAIL (exploration)

**Primary verdict:** ALSA `plughw` after recovery.

| | |
|-|-|
| PASS | ALSA playback OK |
| FAIL | ALSA still broken |

S1–S4 signature = **observations** (logged, not PASS/FAIL).

Post-PASS: **one suspend** (`RESOLUTION_SUSPEND_ONCE=1` default) — suspendible again?

---

## Signature

| Phase | Required |
|-------|----------|
| Exploration | S1–S4 (advance on PASS) |
| Consolidation | S1–S5 |

---

## Gates

| Goal | Threshold |
|------|-----------|
| Research (narrow question) | PROMISING + confidence ≥ **0.85** |
| Workaround hook | **STABLE** (consolidation ×3) |

---

## Related

| Doc | Role |
|-----|------|
| [../edges/state.json](../edges/state.json) | confidence float, status |
| [../scripts/recovery/next-edge.sh](../scripts/recovery/next-edge.sh) | queue logic |
