# Resolution lab — system recovery engineering

English (canonical). **Hypothesis generator** for upstream — not Phase 9.

**Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`

---

## Core question

Not *"what fails?"* but:

> **What minimal action returns the system to a functional state — and which transition was missing?**

[`research/`](../research/frozen/upstream-proof/) answered *where* it breaks. [`resolution/`](../resolution/) finds *which edge restores S3*.

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

## Branches

| Branch | When | Entry |
|--------|------|-------|
| **Recovery** | always | [recovery/PROTOCOL.md](recovery/PROTOCOL.md) |
| **Boot replay** | R04/R07 partial PASS | [experiments/R002-boot-sequence-replay.md](experiments/R002-boot-sequence-replay.md) |
| **Mutation** | need in-resume fix | [experiments/R005-mutation-sequences.md](experiments/R005-mutation-sequences.md) |
| **Firmware** | R09+R07+R08 fail | [firmware/README.md](firmware/README.md) |
| **ACPI/Windows** | parallel | [reverse-engineering/](reverse-engineering/) |

---

## When PASS → research reactivates (Stable Edge only)

| Gate | Requirement |
|------|-------------|
| PASS ×1 | Repeat same edge — **do not** switch |
| 5/5 full signature | incl. suspend #2 on each counted run |
| Stable Edge | `edges/state.json` status `stable` |
| Research | **one** question from edge definition |

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
├── EDGE-FRAMEWORK.md    ← closure ladder, signature, saturation
├── edges/               ← E09… formal contracts + state.json
├── DEPTH-MATRIX.md      ← Cost × Knowledge
├── TRACKER.md           ← transition log
├── UPSTREAM-VALUE.md
├── recovery/PROTOCOL.md
├── firmware/            ← Windows handoff (FW01+)
├── firmware/            ← Windows handoff FW01+
├── experiments/         ← replay + mutation sequences
└── scripts/recovery/    ← R01–R10
```

---

## Rules

- Log **transitions**, not just PASS/FAIL.
- Record Cost **and** Knowledge Gain.
- Explore by K/C; ship by Cost.
- Re-open `research/` only for the specific edge found.
