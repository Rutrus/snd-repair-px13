# Metrics — Cost, Knowledge, EIG

English (canonical). Optimize **uncertainty reduction**, not fact count.

---

## Recovery Cost (1–8)

Lower = cheaper. See [DEPTH-MATRIX.md](DEPTH-MATRIX.md).

---

## Knowledge Gain (1–5)

How much we learn **if** the experiment runs successfully.

---

## K/C

`Knowledge ÷ Cost` — exploration ordering when campaigns are ambiguous.

---

## Expected Information Gain (EIG)

**Expected reduction of uncertainty** — includes FAIL outcomes and kill paths.

| EIG | Meaning | Example |
|-----|---------|---------|
| **enormous** | Kills or confirms dominant hypothesis | Maintainer reply; C01 closure |
| **very_high** | Narrows mechanism class either way | E07 differential (PASS or informative FAIL) |
| **high** | Rules out a recovery domain | E04-style informative FAIL |
| **medium** | Refines competitor | I02 stable Type A/B across 3+ runs |
| **low** | Adds observation, rarely kills | Single I02 run, one new fact |

**Priority rule:** Prefer highest **EIG** among active campaigns, not highest K/C.

```text
Goal: minimize uncertainty
Not:  accumulate facts
```

---

## Comparison table

| Action | Cost | K/C | EIG | Campaign |
|--------|------|-----|-----|----------|
| I02 (one run) | 1 | high | **low** | C01 |
| I02 (boot+S2+post-E07) | 3 | high | **medium** | C01+C02 |
| **E07** Reprobe | 4 | 1.25 | **very_high** | C02 |
| E04 Recover | 2 | 1.50 | high (done) | — |
| E09 Replay | 3 | 1.67 | high (BLOCKED) | C04 parked |
| Maintainer reply | 0 | ∞ | **enormous** | C01 |
| New patch A/B/C | 6+ | low | **very_low** | — (see negative/) |

---

## Weekly principle

> **Kill one big hypothesis per week** — not ten small facts.

Campaign `weekly_kill_target` in [campaigns/](campaigns/README.md) defines the hypothesis at stake.

---

## Edge Result vs Knowledge Result

| Report field | Meaning |
|--------------|---------|
| **Edge Result** | ALSA recovery PASS / FAIL / BLOCKED |
| **Knowledge Result** | Did uncertainty shrink? SUCCESS · ADVANCED · PARTIAL |
| **Campaign Result** | C02 KILLED · C02 CONVERGING · — |

E07 FAIL + 4 gates + `diff=RELEVANT_UNCHANGED` → **Campaign Result: C02 KILLED** (not merely Edge FAIL).

---

## Related

- [campaigns/README.md](campaigns/README.md)
- [scripts/campaigns/campaign-status.sh](scripts/campaigns/campaign-status.sh)
