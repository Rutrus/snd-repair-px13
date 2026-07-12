# Resolution lab — system recovery engineering

English (canonical). **Hypothesis generator** for upstream — recovery lines **paused/frozen** (2026-07-12).

**Unified model:** [../research/UNIFIED-CAUSAL-MODEL.md](../research/UNIFIED-CAUSAL-MODEL.md) — bruteforce/rescue negative results support "state not in PCI layer."

**Active research:** [../research/track-PCM-smartamp-hwparams.md](../research/track-PCM-smartamp-hwparams.md) (Q1: rejecting `hw_params` callback).

**Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`

---

## Fundamental unit

> **The fundamental unit of the project is no longer an experiment; it is a change of confidence in a node of the causal model.**

An experiment ends when it modifies exactly one of: a **fact** · a **hypothesis** · an **edge** · or **confidence / evidence_debt**.

Evidence: [evidence/README.md](evidence/README.md) · Debt: `scripts/evidence/evidence-debt.sh`

---

## Core question (2026-07-12)

Primary (research — Q1):

> **Which kernel callback returns `-EINVAL` on PCM2 (`hw:1,2`) after resume?**

Secondary (resolution — paused until Q1 closes):

> What minimal action returns the system to a functional state — and which transition was missing?

[`research/frozen/upstream-proof/`](../research/frozen/upstream-proof/) documented the **IRQ delivery boundary** (remote cause candidate). [`research/UNIFIED-CAUSAL-MODEL.md`](../research/UNIFIED-CAUSAL-MODEL.md) separates that evidence from PCM2 EINVAL.

---

## Golden rule

> **Change system state. Do not observe.**

| | `research/` | `resolution/` |
|---|-------------|---------------|
| Unit of work | experiment | **state transition** |
| Success | knowledge | S2 → S3 edge + **Knowledge Gain** |
| Re-open research | frozen | **only when stable edge found** |

---

## Methodology

```text
Boot chain → S0
Suspend → S1 → Resume → S2 (missing: STAT1 → IRQ → worker)
Recovery adds one transition → S3?
```

Full chains: [STATE-GRAPH.md](STATE-GRAPH.md)

---

## Two metrics — prioritize by Knowledge ÷ Cost

| Metric | Optimize |
|--------|----------|
| **Recovery Cost** | Lowest for **production** workaround |
| **Knowledge Gain** | Highest for **exploration** |

| ID | Cost | Knowledge | K/C | Run order |
|----|------|-----------|-----|-----------|
| **R09** | 3 | 5 | **1.67** | **1st** |
| R07 | 4 | 5 | 1.25 | 2nd |
| R08 | 5 | 3 | 0.60 | 3rd |
| R01 | 1 | 1 | 1.00 | ladder only |

Table: [DEPTH-MATRIX.md](DEPTH-MATRIX.md) · log: [TRACKER.md](TRACKER.md)

**Explore** R09 → R07 → R08. **Ship** cheapest stable PASS.

---

## R09 first

If `runtime_suspend → runtime_resume` reaches S3:

> Hardware **can** recover. Only **system PM sequence** is wrong.

Research re-opens narrowly: *what does runtime PM do that system PM does not?*

If R09 fails: `runtime_resume` shares the bug → go deeper (R07, R08, [firmware/](firmware/)).

---

## Weekly principle

> **Kill one big hypothesis per week** — not ten small facts.

Active campaigns (max 2): [campaigns/README.md](campaigns/README.md)

```bash
~/snd_repair/resolution/scripts/campaigns/campaign-status.sh
```

Metrics: [METRICS.md](METRICS.md) (Cost · Knowledge · **EIG**) · Exit: [EXIT-CRITERIA.md](EXIT-CRITERIA.md)

---

## Three dimensions

```text
research/     frozen archaeology
resolution/   campaigns → edges → inspectors
evidence/     invariants → facts → hypotheses
negative/     rejected fixes (patches + recoveries)
```

| Layer | Role |
|-------|------|
| [campaigns/](campaigns/README.md) | What we prove **this week** (≤2 active) |
| [evidence/invariants.yaml](evidence/invariants.yaml) | Stable measurements |
| [evidence/facts.yaml](evidence/facts.yaml) | Volatile only |
| [negative/rejected-fixes.yaml](negative/rejected-fixes.yaml) | Do not repeat |

---

## Branches

| Branch / line | Goal | Status | Entry |
|---------------|------|--------|-------|
| **Track PCM2** | Q1: rejecting hw_params callback | **Active** | [../research/track-PCM-smartamp-hwparams.md](../research/track-PCM-smartamp-hwparams.md) |
| `resolution/lab` | Causal model, evidence, C01 | **Paused** | [campaigns/](campaigns/) |
| **`resolution/bruteforce`** | Negative: rebuild ≠ fix | **Frozen** | [bruteforce/README.md](bruteforce/README.md) |
| Recovery ladder | R04–R10 state transitions | **Paused** | [recovery/PROTOCOL.md](recovery/PROTOCOL.md) |
| Phase 6–8 upstream | IRQ boundary mail | **Frozen** | [../research/frozen/upstream-proof/](../research/frozen/upstream-proof/) |

---

## Gates (exploration first)

| Goal | Threshold |
|------|-----------|
| **Research** (Option A) | PROMISING + confidence ≥ **0.85** |
| **Workaround** (Option B) | **STABLE** — consolidation sprint ×3 |

One PASS on E09 (research-coherent) may reach 0.85 **without** five repeats.

Details: [EDGE-FRAMEWORK.md](EDGE-FRAMEWORK.md) · [edges/E09.md](edges/E09.md)

---

## Definition of done

| Phase | Goal |
|-------|------|
| 1 | Documented transition S2 → S3 (Cost + Knowledge) |
| 2 | Automated hook / patch |
| 3 | Research explains why → upstream |

---

## Layout

```
resolution/
├── README.md
├── campaigns/           ← C01, C02 active (max 2)
├── evidence/
│   ├── invariants.yaml
│   ├── facts.yaml       ← volatile only
│   ├── hypotheses.yaml
│   └── confidence.yaml
├── negative/            ← rejected-fixes.yaml
├── METRICS.md           ← EIG
├── EXIT-CRITERIA.md
├── observability/
├── EDGE-TYPES.md
└── scripts/
    ├── campaigns/campaign-status.sh
    ├── evidence/evidence-debt.sh
    └── inspectors/
```

---

## Rules

- Log **transitions**, not just PASS/FAIL.
- Record Cost **and** Knowledge Gain.
- Explore by K/C; ship by Cost.
- Re-open `research/` only for the specific edge found.
