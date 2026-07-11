# Phase 8 — ACP platform IRQ path (ACP70)

English (canonical). **Phase 7 is frozen** — do not add SoundWire manager experiments (delays, manual schedule, STAT decode sweeps).

**Upstream context:** [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md)

**Prerequisite patches:** Phase 6 observation base (0003–0007). Phase 7 patches **not required** for Phase 8 unless reusing 0007 pci-ps probes.

---

## Open gap (only uncertainty left)

```text
resume
   │
   ▼
manager_reset → bring-up OK (ret=0)
   │
   ▼
STAT1 & mask = 0x4 (~50 ms)          [Fact — Phase 7]
   │
   ▼
?????????????????????                  [Phase 8]
   │
   ▼
acp63_irq_handler()                    [Fact: not invoked on resume]
   │
   ▼
schedule_work → irq_thread → ATTACHED [Fact: OK if forced — 0006a experiment]
   │
   ▼
RT721 OK
```

**Phase 8 does not ask “what fails in SoundWire?”** It asks **where between STAT and `acp63_irq_handler()` the resume path diverges from boot.**

---

## Out of scope (do not repeat)

- Phase 7 delays, timers, manual `schedule_work`, STAT decode sweeps
- RT721 / TAS2783 / `bus.c` / PipeWire unless new evidence contradicts Phase 7

---

## Mini-objectives

### 8.1 — Locate the exact boundary (observation only)

**Question:** Does the CPU receive an interrupt that the handler ignores, or does no interrupt reach the Linux IRQ layer?

Current facts:

- Manager reads pending `STAT1 & mask`
- `acp63_irq_handler()` is not entered on resume

Unknown:

```text
hardware → IOAPIC → generic_handle_irq → acp63_irq_handler
```

vs

```text
hardware → (lost before Linux)
```

**Instrumentation (no behaviour change):**

| Probe | Where |
|-------|--------|
| `request_irq` / flags / irq number | `pci-ps.c` (extend 0007 if needed) |
| `enable_irq` / `disable_irq` | suspend + resume path |
| Handler entry counter + last status | `acp63_irq_handler` top (atomic counter, optional debugfs) |
| `/proc/interrupts` | `scripts/phase7-irq-snapshot.sh` **pre-suspend and post-resume, same boot, N cycles** |

**Pass criteria for 8.1:**

- Same-boot IRQ count: increments on boot enumeration; **no increment** during resume window while STAT pending — strengthens “never delivered” vs “delivered but filtered before our log”
- If counter > 0 on resume but no `irq_handler_enter` log → logging/filter issue (unlikely)
- If counter == 0 and `/proc/interrupts` unchanged → boundary before handler

---

### 8.2 — Boot vs resume diff (ACP only)

**Question:** What differs in ACP platform setup between cold boot and first s2idle resume?

Do **not** compare SoundWire manager sequences (already matched). Compare **ACP / pci-ps** only.

| Point | Boot | Resume |
|-------|------|--------|
| `request_irq` | ✓ | ✓ |
| IRQ number / GSI | | |
| `msi` | 0 | 0 |
| IRQ enabled (driver view) | | |
| IRQ affinity / mask | ? | ? |
| `ACP_EXTERNAL_INTR_CNTL*` | | |
| `ACP_EXTERNAL_INTR_STAT*` at handler entry | | |
| `acp70_enable_interrupts` path | | |
| host-wake CNTL1 write | N/A | ✓ (0007 correlate) |

**Method:** extend observation patches in `sound/soc/amd/ps/` only; one binary question per patch.

---

### 8.3 — Read and diagram ACP70 IRQ flow (top-down)

**Goal:** Document the intended path from hardware to `schedule_work()` — not hunt bugs yet.

**Files (priority order):**

```text
sound/soc/amd/ps/pci-ps.c
sound/soc/amd/ps/ps-common.c
sound/soc/amd/ps/acp70*
```

**Deliverable:** [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) — diagram:

```text
STAT (ACP_EXTERNAL_INTR_STAT*)
        ↓
ACP interrupt controller / mask
        ↓
legacy IRQ (ACP_PCI_IRQ)
        ↓
acp63_irq_handler()
        ↓
sdw1_irq() / branch
        ↓
schedule_work(amd_sdw_irq_thread)
```

Mark each step with boot-only / resume / both from code read.

---

## Parallel track — upstream outreach

While running 8.1–8.3 locally, ask maintainers (ALSA list or direct):

> Is it familiar that ACP70 shows pending SoundWire STAT after s2idle resume but `acp63_irq_handler` is never entered, while cold boot with the same STAT bit invokes the handler?

Attach: [UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) executive summary + investigation tree.

---

## Roadmap

| Step | Action |
|------|--------|
| 1 | Phase 7 frozen ✅ |
| 2 | Upstream draft polished ✅ |
| 3 | **8.1** — [0008 irq-boundary-trace](experiments/0008-irq-boundary-trace.md) + `build-phase8.sh` |
| 4 | **8.2** — boot vs resume table in `pci-ps.c` |
| 5 | **8.3** — [ACP-IRQ-FLOW.md](ACP-IRQ-FLOW.md) from code read |
| 6 | Decide: candidate patch **or** upstream report with acutely bounded question |

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0008-irq-boundary-trace.md](experiments/0008-irq-boundary-trace.md) | **8.1** in progress |
| [../phase-7/INDEX.md](../phase-7/INDEX.md) | Frozen experiments |
| [../phase-7/experiments/0007-run-correlate-d50.md](../phase-7/experiments/0007-run-correlate-d50.md) | Delivery witness |
| [../JOURNEY.md](../JOURNEY.md) | Full thread |
