# Investigator Q&A — answers from existing evidence

English (canonical). Draft reply to external review (2026-07-11). **No new experiments required** for most items — cites runs 0014/0015, p7-correlate-d50, p8-boundary-c1, and static code read.

**Related:** [ACP-BOOT-VS-RESUME-CALLS.md](ACP-BOOT-VS-RESUME-CALLS.md) · [experiments/0008-run-boundary-c1.md](experiments/0008-run-boundary-c1.md)

---

## Can we respond now?

**Yes — for delimitation, STAT1 ack paths, pre-unmask timeline, and call-sequence audit.**  
**Partially — for edge-trigger mechanism** (hypothesis compatible with data but not proven; one refined sub-case is **ruled out** by logs).  
**No — for root-cause fix** without one single-variable patch test (STAT1 clear before unmask is the leading experiment, not yet run).

---

## 1. Boundary — what is closed?

| Claim | Evidence |
|-------|----------|
| HW sets manager-visible pending bit | `intr_decode post_delay`: `STAT1=0x4`, `STAT&mask=0x4` (0006b/0007/p8) |
| Linux never accounts for IRQ on resume | `/proc/interrupts` delta=0 on IRQ 160 (8.1) |
| Handler never runs | `handler_since_pm=0`, no `irq_handler_enter resume≥1` (8.1) |
| SDW stack is viable | 0006a: manual `schedule_work` → ATTACHED → RT721 OK |
| SoundWire manager / RT721 / DMA watermarks not primary | Phase 7 + boot first IRQ at `CNTL1=0x4` only |

**Inference:** gap is **ACP MMIO STAT pending → legacy IRQ delivery → `acp63_irq_handler()`**, not downstream SDW.

---

## 2. Is STAT1 cleared anywhere outside the handler?

**No — for the manager bit `ACP_SDW1_STAT` (`0x4`).**

Full-tree grep (`linux-source-7.0.0`): only `pci-ps.c` writes `ACP_EXTERNAL_INTR_STAT1`.  
`ACP_SDW1_STAT` ack appears **only** in `acp63_irq_handler()`.  
Other STAT1 writes (host-wake, PME, DMA thresholds) are **different bits**, all reached **from the handler** on the IRQ path.

`acp70_disable_interrupts()` clears **STAT0** only; never STAT1.

**Consequence on resume:** the `0x4` pending bit is **not silently consumed** by wake/DMA/deinit code. It stays latched while the handler never runs.

---

## 3. Is STAT1 zero immediately before manager unmask (pre-enable)?

**Yes — with existing logs, not a blind spot.**

Timeline on FAIL resume (runs 0014, 0015, p7-correlate-d50, p8-boundary-c1):

| Milestone | When | STAT1 (link 1) | Source |
|-----------|------|----------------|--------|
| After PCI `acp70_init` | `pm_resume_done` | **`0x0`** | PHASE7 pci-ps reads `ACP_EXTERNAL_INTR_STAT1` |
| After `amd_enable_sdw_interrupts()` | `intr_stat_post_enable` | **`0x0`** | manager reads `ACP_EXTERNAL_INTR_STAT(1)` = **STAT1** (`amd_manager.h`: STAT0 + instance×4) |
| After bring-up | `intr_stat_post_bringup` | **`0x0`** | same register |
| After D0 | `intr_stat_post_D0` / `post_D0` | **`0x0`** | 0006b `intr_decode` |
| ~50 ms after D0 | `post_delay` | **`0x4`** | 0006b |
| Handler | — | **never** | 0007/0008 |

**Answer:** STAT1 is **0** through enable, unmask (`CNTL1=0x400004`), and D0. The pending bit appears **later** as a **0→4 transition**, not as “already high before unmask.”

That **rules out** the simple edge scenario:

```text
STAT1 already high → unmask → no new edge → no IRQ   ✗ (not what logs show)
```

What logs **do** show:

```text
unmask with STAT1=0 → ~50 ms later STAT1 0→4 → still no Linux IRQ / no handler   ✓
```

Boot contrast: same `STAT1=0x4` → **immediate** `irq_handler_enter` → ack → thread.

---

## 4. Edge-trigger hypothesis — refined

The investigator’s level/edge framing is still useful, but evidence points to a **stricter** question:

> Why does a **new** STAT1 rising bit (after clean pre-unmask reads) fail to produce a legacy IRQ edge on resume, while the same transition on boot does?

Possible layers (not mutually exclusive):

1. **Bridge re-arm** after s2idle — ENB/CNTL look correct but line never pulses (fits 8.1).
2. **Lost edge at ENB/host-wake enable** — less likely here because `pm_resume_done` already has ENB=1 and STAT1=0.
3. **IO-APIC / GSI / firmware** — STAT latched in ACP; CPU side never counts (fits delta=0).

We **cannot** confirm level vs edge from driver code alone; we **can** say the “stale STAT before manager unmask” variant is **inconsistent with measured timeline**.

---

## 5. `pci_set_master()` — why deprioritize?

Agree with investigator: **weak first candidate.**

- MMIO works (`acp70_init`, manager, STAT reads/writes).
- `pci_set_master` affects PCI bus mastering, not legacy INTR pin enable directly.
- Worth a **cheap falsification test later**, not priority 1.

---

## 6. probe() vs resume() vs runtime_resume() — call differences

### PCI driver (`pci-ps.c`)

| Call | `probe` | `snd_acp_resume` (system sleep) | `snd_acp_runtime_resume` |
|------|---------|----------------------------------|---------------------------|
| `pci_enable_device` | ✓ | — | — |
| `pci_set_master` | ✓ | — | — |
| `acp_hw_init` → `acp70_init` | ✓ | ✓ (via `snd_acp70_resume` full path) | ✓ (full path only) |
| `devm_request_threaded_irq` | ✓ | — | — |
| Platform / machine setup | ✓ | — | — |
| Pad restore | — | ✓ `snd_acp70_resume` | — |
| PM trace | — | PHASE7/8 `pm_resume_*` | — |

**`snd_acp70_resume` vs `snd_acp70_runtime_resume` (ps-common):**

| | System resume | Runtime resume |
|---|---------------|----------------|
| Fast path (`sdw_en_stat`) | ZSC=0, PME=1 | ZSC=0, PME=1 |
| Full path | `acp_hw_init` + **pad restore** | `acp_hw_init` only |
| ACP63-only | — | `handle_acp63_sdw_pme_event()` on full path |

p8 FAIL used **system resume + full init** (not fast path).

### Manager

| | Boot | System resume |
|---|------|---------------|
| Entry | `amd_sdw_manager_start()` | `amd_resume_runtime()` (`SET_SYSTEM_SLEEP_PM_OPS(..., amd_resume_runtime)`) |
| IRQ-relevant tail | `init → enable_irq → enable_manager → frameshape` | same + `clear_slave_status`, clk resume, D0 |
| Precondition | After `request_irq` | No second `request_irq` |

**No missing helper** found at `acp70_enable_interrupts()` level between probe-init and resume-init — **same function**. Differences are **above** (PCI probe-only) and **beside** (manager PM entry, ordering parent-before-child on resume).

---

## 7. Revised patch experiment order

One variable per build; binary question each time.

| Priority | Experiment | Binary question |
|----------|------------|-----------------|
| **A** | W1C clear **`ACP_SDW1_STAT`** before ENB | **❌ FAIL** — [0009-run-falsify-A-fail.md](experiments/0009-run-falsify-A-fail.md) |
| **B** | Zero CNTL1 + W1C STAT1 + zero ENB/CNTL0, then reprogram | **Next** |
| **D** | `pci_set_master()` in `snd_acp_resume()` | After B |
| **C** | `PME_EN` before `enable_interrupts` | After D |
| **E** | `enable_irq(pci->irq)` on resume | [LINUX-IRQ-DESCRIPTOR-AUDIT.md](LINUX-IRQ-DESCRIPTOR-AUDIT.md) |

Build: `./scripts/build-phase8-falsify.sh --patch A|B|C|D` · Protocol: [experiments/0009-falsification-matrix.md](experiments/0009-falsification-matrix.md)

---

## 8. What we would send upstream **today** vs **after one patch test**

**Today (Rama B — hold):** strong bug report — repro, three witnesses, 0006a causality, call/register audit, concrete maintainer question. **No fix claim.**

**After patch test:** if priority 1 or 2 works → submit **3-line fix + evidence**. If all fail → send Rama B with added line: *software re-arm path exhausted in ps/; likely bridge/firmware.*

---

## 9. Short reply text (copy-ready for investigator)

> We can answer the pre-unmask question from existing runs: STAT1 is **0** at `pm_resume_done` (after `acp70_enable_interrupts`), at `intr_stat_post_enable` (after manager CNTL1 unmask), and at `post_D0`. The `0x4` bit appears only at **post_delay (~50 ms)** — a **0→4 transition**, not a stale high level before unmask.  
>  
> `ACP_SDW1_STAT` is acked **only** in `acp63_irq_handler()`; nothing else consumes it on resume. Combined with `/proc/interrupts` delta=0 (8.1), the event stays pending while Linux never sees the IRQ.  
>  
> We agree `pci_set_master` is a weak first candidate; leading experiment is explicit STAT1 clear before interrupt enable/unmask. SoundWire-side work is closed; remaining work is a focused ps/ re-arm audit plus at most 2–3 single-variable patches.

---

## Related

| Doc | Role |
|-----|------|
| [ACP-BOOT-VS-RESUME-CALLS.md](ACP-BOOT-VS-RESUME-CALLS.md) | Full call matrix |
| [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) | Rama B (do not send yet) |
| [INDEX.md](INDEX.md) | Phase 8 roadmap |
