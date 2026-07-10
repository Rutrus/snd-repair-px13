# Phase 6 investigation status (ACP70 / PX13)

English (canonical). Last updated: 2026-07-10 (run **0013** — S1).

**Progress:** ~95% delimitation. **S1 bisect complete** on run 0013; S2 ruled out on that run.

**Canonical facts:** [KNOWN-FACTS.md](KNOWN-FACTS.md)

---

## Problem statement (demonstrated)

> After `manager_reset` and `irq_enabled`, no transition from the ACP manager into SoundWire re-enumeration is observed; RT721 blocks on `initialization_complete()` until `-110`.

---

## Upstream diagram (updated run 0013)

```text
resume
   ↓
manager_reset                    ✅
   ↓
irq_enabled                      ✅
   ↓
intr_stat_post_enable = 0x0        ✅ 0013 (immediate read)
irq_handler_enter                ✗ none in wait window
   ↓
────────────────────────────────  S1 (not S2 on 0013)
   ↓
no ATTACHED / no completion
   ↓
RT721 wait_init_timeout (-110)
```

**Maintainer focus:** why `ACP_EXTERNAL_INTR_STAT` is **0** immediately after enable + `manager_reset` on ACP70 — not codec PM, not IRQ routing (this run).

---

## S1 vs S2 (run 0013)

| Probe | 0013 |
|-------|------|
| `intr_stat_post_enable` | **0x0** |
| `irq_handler_enter` | **NO** |
| `irq_thread_enter` | **NO** |
| Verdict | **S1** |

S2 (stat≠0, no handler) **not observed**. Optional: repeat on another FAIL for confidence; capture PASS with stat≠0 + handler for contrast.

---

## What is proven vs what is not

| Statement | Status |
|-----------|--------|
| Gap after `irq_enabled` | **Observed** (0010, 0012, 0013) |
| S1 pattern on 0013 | **stat=0, no handler** |
| S2 on 0013 | **Ruled out** |
| HW never asserts IRQ (absolute) | **Not claimed** — single post-enable read + no handler in window |
| PASS contrast | **Still wanted** for upstream gold |

---

## Hypotheses (post-0013)

| ID | ~% | Scope |
|----|---:|-------|
| **H-ACP-HW** | **75** | ACP block / FW / sequencing — no pending STAT after reset |
| **H-ACP-TIMING** | 15 | Event after our read (needs STAT poll or PASS trace) |
| **H-SDW** | 10 | Unlikely until IRQ reaches software |

---

## Run reference (recent)

| Run | S1/S2 | Key |
|-----|-------|-----|
| 0010, 0012 | gap only | irq_enabled → silence |
| **0013** | **S1** | `stat=0x0`, no handler; `run-13-s1s2` |

```bash
./scripts/phase6-experiment.sh sm 0013
```

---

## Instrumentation

| Patch | Status |
|-------|--------|
| 0003–0004 | Installed |
| **0005** | **Installed** — S1 confirmed run 0013 |

---

## Exit criteria

- [x] 0005 S1 on clean-boot FAIL (0013)
- [x] S2 ruled out on 0013
- [ ] Optional: second FAIL-1 with 0005 (reproducibility)
- [ ] PASS with same trace (upstream contrast)

---

## Commands

```bash
./scripts/phase6-experiment.sh sm 0013
./scripts/phase6-experiment.sh tl 0013
```
