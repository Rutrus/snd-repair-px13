# C3 / C4 — Post-resume delay

English (canonical). Track **C** (kernel patch).

**Goal:** if IRQ delivery is late, delaying `acp70_enable_interrupts()` or manager reset may allow bridge to arm.

**Status:** `?` — research 0005 (delay after D0 only) was **FAIL**; this tries **different anchor points**.

---

## Variants to patch (one per build)

| Id | Insert delay after | ms |
|----|-------------------|-----|
| C3a | `acp_hw_resume()` entry | 200 |
| C3b | manager_reset complete | 200 |
| C3c | `acp70_enable_interrupts()` | 200 |
| C4a | same anchors | 500 |

**Do not** combine with 0006a manual schedule — that proves sufficiency, not timing.

---

## Build

Use `resolution/scripts/` or fork `scripts/build-phase7.sh` with resolution patch name.

---

## Research baseline (already FAIL)

[../../research/phase-7/experiments/0005-delay-after-d0.md](../../research/phase-7/experiments/0005-delay-after-d0.md) — STAT appears @ +50 ms; handler still missing.

---

## Result

| Build | Delay point | ms | Result | Notes |
|-------|-------------|-----|--------|-------|
| — | — | — | — | |
