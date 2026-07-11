# Upstream report — ACP70 SoundWire s2idle resume (ASUS ProArt PX13)

English (canonical). **Submittable** — experimental reduction complete through Phase **8.3** (0010 PCI INTx observation).

**Local investigation:** **frozen** after 0010 unless a maintainer points to a specific register or sequence.

Related detail: [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) (long-form) · [experiments/0010-run-pci-intx-observe.md](experiments/0010-run-pci-intx-observe.md)

Legend: **Fact** = repeated kernel witness · **Inference** = reasonable conclusion · **Not demonstrated** = out of scope

---

## Reproduction context

| Field | Value |
|-------|--------|
| Running kernel | `7.0.0-27-generic` (Ubuntu) |
| Kernel source package | `linux-source-7.0.0` **7.0.0-27.27** (distro tarball, not a git clone) |
| Instrumented tree | `linux-source-7.0.0/` — vanilla Ubuntu source + local patches only |
| Investigation repo commit | `d6a445a827724719aa00b38fc6550ebbd0b5ccc6` — branch `research/suspend-lifecycle` |
| Definitive 0010 run | 2026-07-11 19:12:32 local time |

Patches applied on top of the vanilla tree are listed under `research/phase-6/proposed/`, `research/phase-7/proposed/`, and `research/phase-8/proposed/` in the investigation repository.

### Instrumentation patches (0010 build)

| Patch | Purpose | Behaviour change |
| ----- | ------- | ---------------- |
| 0006b | STAT timing / decode trace | No |
| 0007 | IRQ handler delivery trace | No |
| 0008 | IRQ counters (`handler_since_pm`, `/proc/interrupts` witness) | No |
| 0010 | PCI INTx status observation at `post_delay` | No |
| 0006a | Manual `schedule_work(amd_sdw_irq_thread)` at `post_delay` | **Yes** (validation only; not in 0010 build) |
| 0009 A | STAT1 preclear before ENB on resume | **Yes** |
| 0009 B | INTR block cold-reset on resume | **Yes** |
| 0009 E | `enable_irq()` at start of `snd_acp_resume()` | **Yes** |

---

## 1. Hardware and kernel

| Field | Value |
|-------|--------|
| Machine | ASUS ProArt PX13 (HN7306EAC) |
| ACP | **ACP70** (PCI rev `0x70`, device `1022:15e2`) |
| SoundWire | Manager **instance 1** (link 1) |
| Codecs | Realtek **RT721** + dual TAS2783 |
| Kernel | `7.0.0-27-generic` (Ubuntu) |
| Suspend | s2idle (`systemctl suspend`) |
| IRQ | Legacy INTx — `ACP_PCI_IRQ`, GSI 13, `msi=0` (IRQ 160 on 0010 run) |

---

## 2. Reproduction

```text
boot → systemctl suspend → resume → RT721 wait_init_timeout (-110)
```

Reproduces with observation-only kernel instrumentation (no behaviour change on the vanilla path). No userspace recovery required.

---

## 3. Causal chains (boot vs resume)

### Boot — **Fact**

```text
manager probe / reset
        │
STAT1 = 0x4  (ACP_EXTERNAL_INTR_STAT1, SDW1 manager bit)
        │
PCI_STATUS.Interrupt Status = 1   (INTX_DISABLE = 0)     [0010]
        │
INTx delivered
        │
acp63_irq_handler() → schedule_work(amd_sdw_irq_thread)
        │
SoundWire ATTACHED → RT721 OK
```

### Resume — **Fact**

```text
manager_reset → D0 (ret=0)
        │
STAT1 = 0x4  (~51 ms after post_D0)
        │
PCI_STATUS.Interrupt Status = 0   (INTX_DISABLE = 0)     [0010]
        │
(no INTx · /proc/interrupts delta=0 · handler_since_pm=0)
        │
acp63_irq_handler() never runs
        │
RT721 wait_init_timeout (-110)
```

### Downstream sufficiency — **Fact** (experiment 0006a only, not a proposed fix)

When `schedule_work(&amd_sdw_irq_thread)` is triggered manually at `post_delay` with the same `STAT1=0x4`, full enumeration and RT721 success occur — **without** `acp63_irq_handler()` running.

---

## 4. Negative-proof table

| Experiment | Layer tested | Result |
|------------|--------------|--------|
| **0006a** | Downstream SDW path (worker thread) | Manual `schedule_work` **restores** enumeration |
| **0006b** | STAT identity / timing | `STAT1=0x4` @ ~50 ms post-D0 on resume |
| **0007** | Handler vs STAT (same build) | STAT pending, **handler absent** |
| **0008** | Linux IRQ accounting | `/proc/interrupts` **delta=0**; `handler_since_pm=0` |
| **Patch A** | STAT1 preclear before ENB | **FAIL** — same symptom |
| **Patch B** | INTR block cold-reset | **FAIL** — same symptom |
| **Patch E** | `enable_irq()` on system resume | **FAIL** — same symptom |
| **0010** | PCI config vs STAT1 | **Case B:** boot `intx_status=1`, resume `intx_status=0` at same `STAT1=0x4` |

---

## 5. Reasoning consistency (four checks)

### 5.1 Why does `STAT1=0x4` correspond to the expected SDW1 manager event?

**Fact:**

- 0006b decodes instance 1, manager mask `0x4`, register `ACP_EXTERNAL_INTR_STAT1` (bit 2 = `ACP_SDW1_STAT`).
- On **boot**, `STAT1=0x4` is immediately followed by `irq_handler_enter` → `sdw1_irq` → `schedule_work` → ATTACHED on dev 1–3 → RT721 success (0007, same observation build).
- On **resume**, the same `STAT&mask=0x4` at `post_delay` occurs without handler entry; RT721 times out **after** this witness (not before).
- 0006a shows that once the **existing** worker runs (same code path the handler would trigger), enumeration completes — so the pending bit is **functionally relevant**, not a unrelated spurious latch.

**Inference:** `STAT1=0x4` on instance 1 is the same class of manager-visible SDW1 event as on boot; the failure is **delivery**, not mis-identification of the bit.

---

### 5.2 Why is `PCI_STATUS.Interrupt Status` interpretable on this device?

**Fact:**

- ACP70 uses **legacy INTx** (`msi=0`, IO-APIC `ACP_PCI_IRQ`).
- PCI Local Bus Spec: Status bit 3 reflects the device's interrupt state; with Command bit 10 (`INTX_DISABLE`) clear and Status bit 3 set, INTx# should be asserted.
- Linux `pci_check_and_mask_intx()` in `drivers/pci/irq.c` uses the same bit for shared-IRQ demux — same semantics the kernel relies on elsewhere.

**0010 boot baseline (same device, same boot):**

```text
PHASE10 when=irq_handler resume=0 stat1=0x4 intx_disable=0 intx_status=1
→ irq_handler_enter → sdw1_irq
```

**Inference:** On this platform, `intx_status=1` correlates with handler delivery when `STAT1=0x4`. If the bit were meaningless on this device, boot would not show this pairing.

**Not demonstrated:** Physical pin level at the IO-APIC; we observe PCI config space and Linux delivery only.

---

### 5.3 Why is a Linux IRQ-descriptor problem unlikely?

**Fact:**

- Patch **E** added explicit `enable_irq(pci->irq)` at the start of `snd_acp_resume()` — **no change** (`handler_since_pm=0`, same `STAT1=0x4`, RT721 `-110`).
- 0008 / 0010: `/proc/interrupts` on IRQ 160 **delta=0** across s2idle; descriptor remains registered (`actions=ACP_PCI_IRQ`, unchanged affinity).
- On boot, the **same** IRQ descriptor and handler function deliver immediately after probe — failure appears only after s2idle, not at registration time.

**Inference:** A permanently broken or wrong handler is unlikely; the gap is **resume-specific** and **after** 0010 still present with descriptor explicitly re-enabled.

---

### 5.4 What did we intentionally **not** modify?

To avoid confounding downstream logic while isolating delivery:

- **SoundWire manager enumeration / attach logic** — after 0006a proved the existing `amd_sdw_irq_thread` path is sufficient when run, we did **not** patch manager state machines, masks beyond observation, or slave drivers.
- **RT721 / TAS2783 codec PM** — observation only; no workaround patches.
- **No speculative `ps-common.c` rewrites** after falsification patches A and B failed identically.
- **0006a `schedule_work` intervention** — used once as a controlled experiment; **not** proposed upstream as a fix.

> We intentionally avoided modifying SoundWire manager bring-up logic after experiment 0006a demonstrated that manually scheduling the existing worker restores enumeration.

Falsification patches (A, B, E) each changed **one** variable; observation 0010 changed **none**.

---

## 6. Conclusion (supported wording)

**Fact:** After s2idle resume, `ACP_EXTERNAL_INTR_STAT1` shows a fresh transition to `ACP_SDW1_STAT` (~51 ms after manager reset) while `acp63_irq_handler()` is not entered and `/proc/interrupts` does not increment.

**Fact (0010):** At that instant, `PCI_STATUS.Interrupt Status` reads **0** with `INTX_DISABLE=0`, whereas on boot with the same `STAT1=0x4` it reads **1** and the handler runs.

**Supported statement:**

> On the investigated platform, after s2idle resume, we consistently observe `ACP_EXTERNAL_INTR_STAT1 = ACP_SDW1_STAT` while `PCI_STATUS.Interrupt Status` remains clear and the registered interrupt handler is never invoked. We were unable to identify the missing propagation step within the publicly available ACP70 driver.

**Not demonstrated:** Internal ACP70 bridge micro-architecture, firmware bug, platform-specific register, or silicon erratum — we do not claim to know **which** step fails to assert PCI Status.

---

## 7. Question for maintainers

> During s2idle resume on ACP70, `ACP_EXTERNAL_INTR_STAT1` transitions from 0 to `ACP_SDW1_STAT` about 50 ms after manager reset, but PCI `Interrupt Status` never becomes asserted (`INTX_DISABLE=0`), so the shared INTx handler is never entered. We were unable to find any ACP70-specific interrupt bridge or re-arm sequence in the public driver beyond `acp70_enable_interrupts()`. Falsification experiments (STAT1 preclear, full INTR block cold-reset, and explicit `enable_irq()` on resume) did not change this behaviour. Is there any platform-specific step — firmware, ACP interrupt bridge, or undocumented register sequence — required after resume before SDW1 events are propagated onto the PCI legacy interrupt?

**Suggested subject:** `ACP70 SoundWire: s2idle resume — STAT1 set but PCI Interrupt Status clear (ASUS PX13)`

---

## 8. Key log excerpts (0010 run, 2026-07-11)

Boot:

```text
PHASE10 ctx=acp fn=pci_intx when=irq_handler resume=0 irq=160 stat1=0x4 intx_disable=0 intx_status=1 t_mgr_ms=-1
PHASE7 ctx=acp fn=irq_handler_enter irq=160 resume=0 ... stat1=0x4 ...
```

Resume:

```text
PHASE7 ctx=amd fn=intr_decode when=post_delay ... STAT1=0x4 STAT&mask=0x4 ... t_since_manager_reset_ms=51
PHASE10 ctx=acp fn=pci_intx when=post_delay resume=1 irq=160 stat1=0x4 intx_disable=0 intx_status=0 t_mgr_ms=51
PHASE8 ctx=acp fn=irq_stats resume=1 handler_total=31 since_pm=0 last_stat1=0x4
rt721-sdca: wait_init_timeout t=+5272ms
```

---

## 9. Attachments (suggested)

Send as **separate reviewable files** (no tarball):

1. This document (`UPSTREAM-REPORT.md`)
2. [0010-journal-excerpt.txt](0010-journal-excerpt.txt) — short `journalctl` excerpt from the 0010 run (optional)
3. IRQ snapshots on request: `validation/.state/irq-pre-suspend-20260711T191155.txt` + `irq-post-resume-20260711T191329.txt`
4. Full logs, scripts, and patch series — **only if a maintainer asks**

See [UPSTREAM-SEND-CHECKLIST.md](UPSTREAM-SEND-CHECKLIST.md).

---

## Appendix A — Driver falsification experiments (detail for maintainers)

Not required to understand the bug; included so reviewers know common software hypotheses were tested.

| Patch | Change | File | Result |
|-------|--------|------|--------|
| **A** | W1C clear `ACP_SDW1_STAT` before `INTR_ENB` on resume | `ps-common.c` | **FAIL** — same `STAT1=0x4`, no handler |
| **B** | Full INTR cold-reset (ENB/CNTL/STAT) before reprogram | `ps-common.c` | **FAIL** — post-reset MMIO all zero; same symptom |
| **E** | `enable_irq(pci->irq)` at start of `snd_acp_resume()` | `pci-ps.c` | **FAIL** — descriptor explicitly re-enabled; no delivery |

Runs: [experiments/0009-run-falsify-A-fail.md](experiments/0009-run-falsify-A-fail.md) · [0009-run-falsify-B-fail.md](experiments/0009-run-falsify-B-fail.md) · [0009-run-falsify-E-fail.md](experiments/0009-run-falsify-E-fail.md)

---

## 10. Local status

| Item | Status |
|------|--------|
| Experimental reduction | **Complete** |
| Candidate driver patch | **None** — awaiting maintainer input |
| Further local patches | **None planned** |
