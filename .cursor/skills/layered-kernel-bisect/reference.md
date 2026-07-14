# Layered kernel bisect — reference templates

## Investigation status doc (skeleton)

```markdown
# [Component] investigation status

**Progress:** ~N% delimitation; blocked on visibility at [layer] (not hypotheses).

## Demonstrated causal chain

[ASCII diagram with ??? at gap]

## Witness vs cause

| Component | Role |
|-----------|------|
| [downstream] | Witness only |
| [upstream] | Active search |

## Failure classes

| Class | Witness | Runs |
|-------|---------|------|
| FAIL-1 | wait → timeout | … |
| FAIL-2 | early_exit, no wait | … |

## Hypotheses (post-[anchor])

| ID | ~% | Break | Log signature |
|----|---:|-------|---------------|

## Binary question (current)

> After [X], does [Y] occur?

## Next instrumentation (minimal)

| # | Location | Log token |
|---|----------|-----------|

## Exit criteria

- [ ] …
```

## Resume path summary block (script output pattern)

```text
=== Resume path (post <anchor>) ===
  anchor_event            YES/NO
  step_1                  YES/NO
  step_2                  YES/NO
  …
  witness_timeout         YES/NO
  correlate_xyz (window)  YES/NO

  fail_class: FAIL-1 | FAIL-2
  → H1? | H2? | H3? | PASS
```

## Minimal kernel probe patch (pattern)

```c
/* Observation only — one line per step */
dev_info(dev, "PHASE ctx=%s fn=%s id=%d t=+%lldms\n",
         "amd", "ping_irq", correlation_id, since_anchor_ms);
```

Rules:
- Log at **entry** of step (before early returns)
- Same `fn=` names in scripts and docs
- Add probe **after** previous step in chain is confirmed reachable

## Build verification snippet

```bash
probe='fn=irq_enabled'
if ! zstdcat "/lib/modules/$(uname -r)/kernel/.../module.ko.zst" | strings | grep -q "$probe"; then
  echo "ERROR: $probe missing from installed module" >&2
  exit 1
fi
```

Check the **gate** probe for the patch series, not a partial sibling.

## PASS vs FAIL contrast table

| Run | anchor | irq | ping | work | ATTACHED | witness | IO_FAULT |
|-----|--------|-----|------|------|----------|---------|----------|
| PASS-… | YES | YES | YES | YES | YES | OK | ? |
| FAIL-… | YES | YES | NO | NO | NO | -110 | YES |

Fill before upstream report.

## Expert principles (verbatim intent)

1. Investigation blocked by **visibility at one point**, not lack of hypotheses.
2. Go **one level above** where the flow disappears — not deeper into answered layers.
3. **Four probes** beat twenty: know if steps **exist**, not full state dumps.
4. The goal shifts from "patch that restores function" to "first event that disappears after [anchor]".
5. That evidence is what **kernel maintainers** need: precise **X→Y** with timing.
