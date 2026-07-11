# Run p8-boundary-c1 — IRQ delivery boundary closed with three witnesses (Phase 8.1)

English (canonical). **2026-07-11** · notes `p8-boundary-c1` · **milestone run**

Build: Phase 6 + **0007 pci-ps** + **0008 irq-boundary-trace** (manager still carries Phase 6/7 observation strings from prior install).

Snapshots:

- `validation/.state/irq-pre-suspend-20260711T171721.txt`
- `validation/.state/irq-post-resume-20260711T171821.txt`

---

## Why this run is a milestone

Phase 7 established that `acp63_irq_handler()` is not entered on resume while `STAT1 & mask = 0x4` is pending. That left one ambiguity: *no printk* is not the same as *handler executed zero times*.

This run closes that gap with **three independent witnesses in one s2idle cycle**:

| Witness | Result |
|---------|--------|
| Hardware pending (`intr_decode post_delay` @ ~51 ms) | `STAT1=0x4` `STAT&mask=0x4` |
| Handler counter (`PHASE8 irq_stats`) | `handler_since_pm=0` `handler_total=365` |
| Linux IRQ layer (`/proc/interrupts` same boot) | IRQ **160** sum **730→730** **delta=0** |

Together: **hardware event present, handler never runs, Linux IRQ counter unchanged.**

Phase 7 **0006a** already showed downstream is viable if `schedule_work()` is forced manually. SoundWire-side instrumentation is therefore **saturated** — further SDW probes add little.

---

## Decision (8.1 closure)

| Evidence | Interpretation |
|----------|----------------|
| `handler_since_pm=0` | **Fact:** `acp63_irq_handler()` not invoked since `pm_suspend_enter` (atomic inc is first line of handler) |
| No `irq_handler_enter resume≥1` | **Fact:** consistent with counter |
| `/proc/interrupts` delta=0 | **Fact:** Linux did not account for a new edge on `ACP_PCI_IRQ` in the suspend→post-resume window |
| `handler_total=365` = IRQ line count 365 | **Fact:** counter matches kernel accounting (cross-check) |

**Closed question:** Not “handler ignores IRQ” — **no delivery to `acp63_irq_handler()` / no Linux IRQ increment** while STAT pending.

**Inference:** Boundary is **before** `acp63_irq_handler()` — ACP interrupt controller → legacy line → IO-APIC → generic IRQ layer.

---

## Kernel excerpts (resume=1)

```text
PHASE8 ctx=acp fn=pm_suspend_enter irq=160 resume=0
PHASE7 ctx=acp fn=pm_resume_enter resume=1 irq=160 msi=0
PHASE7 ctx=acp fn=cntl1_write who=acp70_host_wake old=0x0 new=0xc00000
PHASE7 ctx=acp fn=pm_resume_done resume=1 … stat1=0x0 cntl1=0xc00000 enb=0x1
PHASE8 ctx=acp fn=irq_stats resume=1 handler_total=365 since_pm=0 last_stat0=0x0 last_stat1=0x4
… manager_reset → bring-up OK …
PHASE7 ctx=amd fn=intr_decode when=post_delay … STAT1=0x4 STAT&mask=0x4 CNTL1=0x400004
(no irq_handler_enter resume≥1)
rt721 wait_init_timeout ret=-110
```

**Note on `last_stat1=0x4`:** stale from last boot handler invocation (`sdw1_irq resume=0` @ 17:17:08), not from resume — handler never ran to refresh it.

**Note on `irq_stats` timing:** logged at `pm_resume_done` (before manager_reset). Post-resume snapshot @ 17:18:21 covers the full RT721 timeout window; `/proc/interrupts` still delta=0.

---

## `/proc/interrupts` compare

```text
pre:  irq-pre-suspend-20260711T171721.txt
post: irq-post-resume-20260711T171821.txt
IRQ:  pre=160 post=160
sum:  pre=730 post=730 delta=0
```

Line 160: `IR-IO-APIC 13-fasteoi ACP_PCI_IRQ` · count **365** (per-CPU sum **730**).

---

## Updated investigation tree

```text
STAT1 pending (hardware)                    ✓ Fact
        │
        ▼
Linux /proc/interrupts increment            ✗ Fact (delta=0)  ← 8.1
        │
        ▼
acp63_irq_handler()                         ✗ Fact (since_pm=0) ← 8.1
        │
        ▼
schedule_work → downstream                  ✓ Fact if forced (0006a experiment)
        │
        ▼
RT721 attach                                ✓ boot / ✗ resume
```

---

## Strategy shift after 8.1

| Before 8.1 | After 8.1 |
|------------|-------------|
| Prove handler does not run | **Closed** — use counter + `/proc/interrupts` as citeable facts |
| More SoundWire experiments | **Stop** — SDW path saturated |
| Broad boot vs resume diff | **Narrow** — last `writel()` to ACP IRQ registers before STAT1; register ownership map |

Next: [ACP-IRQ-FLOW.md](../ACP-IRQ-FLOW.md) (8.2 + 8.3) — code audit, not new delays or STAT sweeps.

---

## Related

| Doc | Role |
|-----|------|
| [0008-irq-boundary-trace.md](0008-irq-boundary-trace.md) | Patch / protocol |
| [0007-run-correlate-d50.md](../../phase-7/experiments/0007-run-correlate-d50.md) | STAT pending + no handler log |
| [../INDEX.md](../INDEX.md) | Phase 8 roadmap |
