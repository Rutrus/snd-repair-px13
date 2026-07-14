---
name: layered-kernel-bisect
description: >-
  Bisect intermittent kernel/driver failures by causal-chain delimitation,
  minimal existence probes, and PASS/FAIL contrast — not symptom patching.
  Use when debugging intermittent resume/suspend, race conditions, driver PM
  failures, missing IRQ/workqueue chains, or when investigation is blocked by
  visibility (not hypotheses). Applies to kernel, firmware, and hardware stacks.
---

# Layered kernel bisect

Methodology distilled from expert-led driver investigation: **stop patching symptoms; delimit the first missing event in the causal chain.**

## When to apply

- Intermittent PASS/FAIL (resume, probe, enumeration, timeout `-110`, etc.)
- Downstream error is known but **upstream trigger is not**
- More instrumentation was added but the break point is still unclear
- Team is debating codec/FW/userspace fixes before the **stack layer** is identified

## Core shift

| Wrong frame | Right frame |
|-------------|-------------|
| "Which patch makes it work?" | "Which **event** selects PASS vs FAIL?" |
| "RT721 times out → fix RT721" | "RT721 is a **witness**; find what never ran before timeout" |
| "Add more printk everywhere" | "Answer **one binary question** per experiment" |
| "PING did not run" | "**No log evidence** of PING in this window" |

## Workflow

### Phase 0 — Freeze behavior changes

No functional patches until bisect identifies the layer. Observation-only trace (`printk` / `trace_printk` / existing tracepoints).

### Phase 1 — Draw the causal chain (conservative)

```text
trigger (e.g. system_resume)
    → layer A (controller resume)
    → layer B (bus reset)
    → ???                    ← THE GAP
    → layer C (IRQ / ping)
    → layer D (work / handle)
    → layer E (state ATTACHED / completion)
    → witness (codec wait / -110 / Dummy Output)
```

Rules:
- Mark only what **log evidence** already proves.
- Label the gap `???` explicitly — that is the active search space.
- Move witnesses **below** the gap; deprioritize them as root-cause candidates.

### Phase 2 — One binary question

Reduce the next experiment to a single YES/NO:

> After event **X**, does step **Y** occur within window **W**?

Example: *After `manager_reset`, does the controller receive/process the first IRQ that should start re-enumeration?*

One answer should narrow to **one component** (hardware IRQ, handler, scheduler, core, bus).

### Phase 3 — Instrument **one layer above** the gap

Do **not** add trace where the previous question was already answered.

| Layer already answered | Next instrument |
|------------------------|-----------------|
| Bus never reaches ATTACHED | Controller IRQ → ping → queue_work (not more bus.c) |
| queue_work never runs | IRQ delivery + irq_thread entry (not handle_status) |
| handle_status runs, bus skips | SDW core / bus contract only then |

**Minimal probes:** existence only (`fn=irq_enabled`, `fn=ping_irq`, `fn=queue_work`). No masks, slave states, or hex dumps until the chain reaches that step.

Uniform log shape helps parsing:

```text
PHASE ctx=<layer> fn=<step> id=<correlation_id> t=+<ms>
```

Use a **correlation id** per transaction (e.g. `resume=N` for system resume; `resume=0` = runtime PM noise).

### Phase 4 — Isolated capture window

Anchor analysis at the known event (e.g. `manager_reset`), not boot-wide grep.

- Window: `[anchor - 5s, suspend_exit + 15s]` or equivalent
- Two clocks: journal timestamp **and** kernel `t=+ms` since anchor (for timeouts)
- Save per-run artifacts; compare runs with identical schema

### Phase 5 — Classify outcomes before new hypotheses

Distinguish **failure classes** at the witness layer even when upstream looks identical:

| Class | Witness pattern | Meaning |
|-------|-----------------|---------|
| FAIL-1 | wait → timeout (`-110`) | Witness entered wait; completion never arrived |
| FAIL-2 | early_exit (no wait) | Witness skipped wait — still compatible with broken upstream |

Do not treat userspace "OK/WARN" as PASS if kernel witness shows failure.

### Phase 6 — Hypothesis table with probabilities

Reweight after each run; deprioritize ruled-out layers.

| ID | ~% | Break | Signature |
|----|---:|-------|-----------|
| H1 | … | IRQ never arrives | `irq_enabled` → no `ping_irq` / no HW IRQ log |
| H2 | … | IRQ, empty status | `ping_irq sc=0` → no `queue_work` |
| H3 | … | work, no state change | `queue_work` → no ATTACHED/completion |
| H4 | … | core skip | manager ATTACHED but bus skip |

Update probabilities; do not add H5 for every new curiosity.

### Phase 7 — Correlates, not causes

Track recurring anomalies (e.g. `IO_PAGE_FAULT`, IOMMU) in a PASS vs FAIL table. **Do not assert causality** until at least one true PASS shares or excludes the correlate.

### Phase 8 — Verify instrumentation landed

Before interpreting a run:

```bash
strings module.ko | grep 'fn=expected_probe'
```

Build scripts must check the **critical** probe (not a partial sibling). Partial patch apply is a common false negative.

### Phase 9 — Exit criteria (before behavior patch)

- [ ] Causal chain documented with conservative claims
- [ ] First missing transition **X→Y** with `t=+ms`
- [ ] ≥1 FAIL and ≥1 PASS with same trace schema (or explicit blocker)
- [ ] Failure class + hypothesis ID assigned
- [ ] Patch target layer chosen (not witness unless proven)

## Decision tree (post-anchor)

```text
anchor (e.g. manager_reset) logged?
  NO  → instrument earlier (PM resume entry)
  YES → irq_enabled / enable step logged?
          NO  → code path aborted OR probe missing (verify module)
          YES → HW IRQ / ping_irq logged?
                  NO  → H1 (delivery / scheduling)
                  YES → queue_work logged?
                          NO  → H2 (empty status / early exit)
                          YES → ATTACHED / completion logged?
                                  NO  → H3 (worker / bus)
                                  YES → PASS path — compare timing vs FAIL
```

## Wording for reports (upstream-safe)

| Avoid | Prefer |
|-------|--------|
| "Re-enumeration is broken" | "No log evidence of post-reset ATTACHED/completion in FAIL window" |
| "PING did not execute" | "No `ping_status` / `ping_irq` log with matching correlation id" |
| "IRQ is broken" | "After `irq_enabled`, no `sdw0_irq` or `ping_irq` within 5s" |

Upstream one-liner template:

> After [trigger] on [platform], [reset event] clears [state]. In FAIL cases, transition **X→Y** in [IRQ/work path] does not occur within the wait window; [witness] is downstream.

## Anti-patterns

- **Shotgun printk** — each layer answers one question; remove verbose probes when minimal chain suffices
- **Instrument callee before caller is proven** — e.g. `handle_status` before `queue_work` exists
- **Boot-wide grep** — mixes `resume=0` runtime noise with system resume
- **Chasing codec/FW** while bus completion never fires
- **Single FAIL run** as definitive — need PASS/FAIL contrast or explicit H1 confirmation on multiple FAILs
- **Composite userspace PASS** while kernel witness fails

## Agent checklist (per iteration)

```
- [ ] Causal chain updated (what is proven vs gap)
- [ ] Single binary question stated
- [ ] Next probe is one layer above gap (minimal)
- [ ] Correlation id filters runtime vs system path
- [ ] Capture window anchored; kernel t=+ for waits
- [ ] sm / summary: YES/NO per step + fail_class
- [ ] Module strings verify critical probe present
- [ ] Claims use "no log evidence" where appropriate
- [ ] Hypothesis table updated
```

## Project example (snd_repair Phase 6)

Reference implementation: `research/phase-6/PHASE-6-INVESTIGATION-STATUS.md`

```bash
./scripts/phase6-experiment.sh arm --notes run-N
systemctl suspend
./scripts/phase6-experiment.sh sm RUN_ID   # Resume path YES/NO block
./scripts/phase6-experiment.sh tl RUN_ID   # timeline anchored at manager_reset
```

Probes: `resume_enter` → `irq_enabled` → `sdw0_irq` → `ping_irq` → `queue_work` → bus ATTACHED → completion.

Further templates: [reference.md](reference.md)
