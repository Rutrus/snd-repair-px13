# Edge framework — exploration first, consolidate last

English (canonical). Optimizes **investigator time**, not CPU. Each suspend/reboot cycle is expensive.

**v2.1:** Recovery runs only after **Witness VALID** (see [WITNESS-QUALITY.md](WITNESS-QUALITY.md)).

---

## Edge types (v2.2)

Recover · Replay · Reprobe · Reconstruct — see [EDGE-TYPES.md](EDGE-TYPES.md).

---

## Witness gate (v2.1)

Before any recovery:

```text
S0 → suspend → Witness oracle (W0–W4)
                    │
         INVALID ───┴─── VALID (≥ W2)
              │              │
     NOT_EXECUTABLE      run Rxx + signature
```

| Witness | Edge result |
|---------|-------------|
| **INVALID** | **NOT_EXECUTABLE** — no confidence update |
| **VALID** | PASS / PARTIAL / FAIL — measures S2→S3 |

Prior E09/E07/E08 **PARTIAL** results without VALID witness are **ambiguous** — re-run after `s2-reproduce.sh`.

---

## Two phases

| Phase | Goal | Repeat? |
|-------|------|---------|
| **Exploration** | Map transitions — maximize new information per cycle | **No** — one PASS → next edge |
| **Consolidation sprint** | Robustness on best candidates only | **Yes** — ×3 per PROMISING edge |

```text
Exploration:
  E09 → PASS? → E07 → PASS? → E08 → … → no higher-priority branches left

Consolidation sprint:
  best PROMISING edge ×3
  (optional) second-best ×3 if workaround candidate
```

---

## Edge lifecycle (not 5/5)

```text
NEW        never PASS, or only FAIL
    ↓
PROMISING  PASS ×1 (signature S1–S4) OR confidence ≥ 0.60
    ↓
STABLE     consolidation ×3 complete OR confidence ≥ 0.95
```

| Status | Meaning |
|--------|---------|
| **NEW** | Hypothesis; run once in exploration |
| **PROMISING** | Evidence of S2→S3; **do not repeat** during exploration |
| **STABLE** | Consolidated; research gate or production hook |

Research may open on **PROMISING** if Option A (unlocks question).  
Workaround hooks need **STABLE** (Option B).

---

## Dynamic confidence (0.0–1.0)

Not all confidence comes from repetition. **Coherence with prior research counts.**

| Evidence | Confidence |
|----------|------------|
| PASS once (S1–S4) | **0.60** |
| + coherent with frozen research | **0.75** |
| + unlocks focused research question | **0.85** |
| + consolidation repeat (each) | **+0.05** (cap **0.95**) |
| Consolidation ×3 complete | → status **STABLE** |

Example: **E09 PASS once** + research already delimited system PM vs IRQ → **0.75–0.85** without five repeats.

Tracked in [edges/state.json](edges/state.json) as `confidence` (float).

---

## Exploration-first rule

> While a **higher-priority unexplored** edge exists, **do not repeat** a PROMISING edge.

```text
E09 PASS
    ↓
Any edge in queue still NEW (not saturated)?
    yes → run next in queue (E07)
    no  → consolidation sprint on PROMISING edges
```

Queue (default): **E09 → E07 → E08 → E04 → FW01**

**Paused** until witness gate passes. Then re-test edges in order **E04 → E07 → E08 → E09** (or resume queue) with VALID S2.

Breadth-first with K/C heuristic — widen the map before confirming one path.

---

## When to freeze an edge

### Option A — Research advance (PROMISING enough)

PASS unlocks a **single** new research question → mark `research_ready: true` → may re-open research at **0.85** confidence without STABLE.

### Option B — Workaround candidate

PASS is usable daily → run **consolidation sprint ×3** (incl. suspend #2 on last run) → **STABLE** → ship hook.

---

## Recovery Signature

| Level | Checks | When |
|-------|--------|------|
| Exploration PASS | S1–S4 | Enough to advance queue |
| Consolidation | S1–S5 (incl. suspend #2) | STABLE / workaround |

Witness: `scripts/recovery/witness-signature.sh`

---

## Information saturation

3 consecutive FAIL (zero Knowledge Gain) on one edge → branch **saturated** → skip in queue.

---

## Structured report

```text
=== RESOLUTION EDGE REPORT ===
Phase:           exploration | consolidation
Witness:         VALID (W3) | INVALID (W1)
Witness Detail:  research S2: -110 + handler_since_pm=0 + STAT1=0x4
Edge:            E09
Result:          PASS | PARTIAL | FAIL | NOT_EXECUTABLE
Status:          NEW → PROMISING
Confidence:      0.75 (research-coherent)
Transition:      S2 → S3
Next Candidate:  s2-reproduce.sh | E04
==============================
```

---

## Research gate

| Gate | Threshold |
|------|-----------|
| Open research (narrow question) | PROMISING + `research_ready` + confidence ≥ **0.85** |
| Ship workaround hook | **STABLE** (consolidation ×3) |

Handoff: [UPSTREAM-VALUE.md](UPSTREAM-VALUE.md)

---

## Related

| Doc | Role |
|-----|------|
| [edges/state.json](edges/state.json) | Machine state |
| [scripts/recovery/next-edge.sh](scripts/recovery/next-edge.sh) | Queue navigation |
| [TRACKER.md](TRACKER.md) | Human log |
