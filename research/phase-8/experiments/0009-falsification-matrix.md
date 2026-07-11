# Phase 8.2 — hypothesis falsification (minimal patches)

English (canonical). **No new printk instrumentation phase** — one behaviour change per build, binary pass/fail.

**Base build:** Phase 6 trace + 0007 + 0008 (observation on `pci-ps.c` only). Falsification patches touch **`ps-common.c`** and/or **`pci-ps.c`** (patch D).

**Prerequisite facts:** [0008-run-boundary-c1.md](0008-run-boundary-c1.md) · [INVESTIGATOR-QA.md](../INVESTIGATOR-QA.md)

---

## Closed chain (no longer in dispute)

```text
resume → acp70_init OK → manager OK
  → STAT1=0 through unmask + D0
  → STAT1=0x4 ~50 ms later
  → no acp63_irq_handler · /proc/interrupts delta=0
  → RT721 -110

schedule_work() → full SDW OK (0006a)
```

SoundWire-side search space is **closed**. Remaining work: falsify ACP / PCI / Linux IRQ delivery hypotheses.

---

## Falsification matrix

| Patch | File | Change | Status |
|-------|------|--------|--------|
| **A** | `ps-common.c` | W1C clear `ACP_SDW1_STAT` before ENB | **❌ FAIL** [0009-run-falsify-A-fail.md](0009-run-falsify-A-fail.md) |
| **B** | `ps-common.c` | **INTR block cold-reset** in `acp70_enable_interrupts()` only | **❌ FAIL** [0009-run-falsify-B-fail.md](0009-run-falsify-B-fail.md) |
| **E** | `pci-ps.c` | `enable_irq(pci->irq)` at start of `snd_acp_resume()` | **❌ FAIL** [0009-run-falsify-E-fail.md](0009-run-falsify-E-fail.md) |
| **D** | `pci-ps.c` | `pci_set_master()` on resume | **Optional** — low prior; falsification phase closed |
| **C** | `ps-common.c` | PME before enable | **Deprioritized** — only if B/E/D inconclusive |

**Order after A:** **B → E → D** (then upstream). **If B fails:** no further `ps-common.c` experiments unless B **passes**.

---

## Patch B — cold-reset sequence (single site)

All changes in **`acp70_enable_interrupts()`** only:

```text
ENB = 0
CNTL0 = 0
CNTL1 = 0
STAT1 W1C (all ones)
STAT0 W1C (all ones)     ← boot parity with disable path
readl(STAT1); readl(CNTL1)   ← flush
log post-reset MMIO
→ normal enable (ENB, CNTL0, host_wake CNTL1)
→ manager resume (unchanged)
```

---

## Patch B — three outcomes

| Outcome | Witness | Meaning |
|---------|---------|---------|
| **1 PASS** | handler resume=1 or `/proc/interrupts` delta>0 | Latent INTR block state was the gap — fix candidate |
| **2 FAIL same** | STAT1=0x4 @ post_delay, IRQ=0 | **High value** — ACP MMIO re-arm exhausted; bridge/architecture |
| **3 STAT gone** | post_delay STAT&mask=0, still no handler | Init order affects event generation — revisit timing only |

---

## After B fails (outcome 2)

Stop inventing `ps-common.c` cleanups. Shift question to:

> What does hardware do between **STAT1 latched** and **INTx visible to Linux**?

Then **E** (Linux descriptor), then **D**, then upstream (~60–70% hardware/bridge per investigator estimate).

---

## Build / restore

```bash
./scripts/build-phase8-falsify.sh --patch B   # auto-runs restore-ps-falsify.sh
# or manual: ./scripts/restore-ps-falsify.sh
```

Patches: [0009b-intr-block-reset.patch](../proposed/0009b-intr-block-reset.patch) · [0009e-enable-irq-resume.patch](../proposed/0009e-enable-irq-resume.patch)

---

## Pass criteria (each run)

After `systemctl suspend` + resume on **clean boot** (`resume=1`):

| Witness | PASS | FAIL (baseline) |
|---------|------|-----------------|
| `PHASE7 irq_handler_enter resume=1` | ≥1 line | absent |
| `/proc/interrupts` IRQ 160 delta | >0 | 0 |
| `PHASE8 handler_since_pm` | >0 | 0 |
| RT721 `wait_init_timeout` | absent / ret=0 | `-110` |
| `intr_decode post_delay STAT&mask` | may be 0x4 with handler | 0x4 without handler |

**Primary binary witness:** `irq_handler_enter resume=1` **or** `/proc/interrupts` delta>0.

---

## Protocol (one patch per run)

```bash
# 1. Build base + exactly one falsification patch
./scripts/build-phase8-falsify.sh --patch B   # then E, then D

# 2. Reboot

# 3. Pre/post IRQ snapshot
./scripts/phase8-irq-snapshot.sh pre-suspend
systemctl suspend
./scripts/phase8-irq-snapshot.sh post-resume

# 4. Log window
journalctl -k -b 0 | grep -E 'PHASE7 ctx=acp fn=irq_handler|PHASE9 ctx=acp fn=falsify|PHASE7 ctx=amd fn=intr_decode when=post_delay'

# 5. Record run
#    validation/phase8-runs/p8-falsify-<patch>-<date>/
```

Log line `PHASE9 ctx=acp fn=falsify patch=X` confirms which experiment was in the module.

---

## Interpretation tree

```text
Patch A fails → stale STAT before ENB ruled out (consistent with pre-unmask logs)
Patch B fails → full block reset before enable not enough
Patch C fails → PME/enable order not enough
Patch D fails → pci_set_master not enough
All fail      → upstream: ACP70 legacy IRQ bridge / firmware after s2idle
                (resume CNTL1=0x400004 is superset of boot 0x4 — SW looks permissive)
```

---

## Why not `pci_set_master` first?

MMIO path fully operational (ENB/CNTL/STAT read/write). `pci_set_master` affects bus mastering (DMA), not INTx assertion. Patch **D** is last intentionally.

---

## Related

| Doc | Role |
|-----|------|
| [../proposed/0009a-stat1-preclear.patch](../proposed/0009a-stat1-preclear.patch) | Patch A |
| [../proposed/0009b-intr-block-reset.patch](../proposed/0009b-intr-block-reset.patch) | Patch B |
| [../proposed/0009c-pme-before-enable.patch](../proposed/0009c-pme-before-enable.patch) | Patch C |
| [../proposed/0009d-pci-set-master-resume.patch](../proposed/0009d-pci-set-master-resume.patch) | Patch D |
| [../LINUX-IRQ-DESCRIPTOR-AUDIT.md](../LINUX-IRQ-DESCRIPTOR-AUDIT.md) | Kernel IRQ desc / wake boundary |
