# Edge catalog

English (canonical). Edges are **transition contracts** — not script names.

Framework: [../EDGE-FRAMEWORK.md](../EDGE-FRAMEWORK.md) · State: [state.json](state.json)

---

## Active exploration order

| Order | Edge | Recovery | Confidence | Status |
|-------|------|----------|------------|--------|
| **1** | [E09](E09.md) | R09 | 0/5 | hypothesis |
| 2 | [E07](E07.md) | R07 | 0/5 | hypothesis |
| 3 | [E08](E08.md) | R08 | 0/5 | hypothesis |
| 4 | [E04](E04.md) | R04 | 0/5 | hypothesis |

Update this table after each run (or from `state.json`).

---

## Edge → script map

| Edge | Script | Layer | Cost | Knowledge |
|------|--------|-------|------|-----------|
| E01 | R01 | L0 | 1 | 1 |
| E02 | R02 | L1 | 2 | 2 |
| E04 | R04 | L2 | 2 | 3 |
| E07 | R07 | L4 | 4 | 5 |
| E08 | R08 | L4 | 5 | 3 |
| E09 | R09 | L4 | 3 | 5 |
| E10 | R10 | L7 | 3 | 2 |
| FW01 | — | L6 | — | 5 |

---

## Saturation

| Branch | Consecutive zero-K | Status |
|--------|-------------------|--------|
| E09 | 0 | active |
| E07 | 0 | active |
| E08 | 0 | active |

Stop branch at **3**. See `state.json`.

---

## Stable edges (research gate)

| Edge | Confidence | Stable? | Research question |
|------|------------|---------|-------------------|
| — | — | — | — |

Only **Stable** rows re-open [../research/](../research/frozen/upstream-proof/).
