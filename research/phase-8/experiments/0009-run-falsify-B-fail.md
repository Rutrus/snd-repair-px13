# Run p8-falsify-B-fail — Patch B falsified (INTR cold-reset in enable path)

English (canonical). **2026-07-11** · boot `7f7f00b9` · Phase **8.2**

Snapshots:

- `validation/.state/irq-pre-suspend-20260711T181734.txt`
- `validation/.state/irq-post-resume-20260711T181829.txt`

Patch: [../proposed/0009b-intr-cold-reset.patch](../proposed/0009b-intr-cold-reset.patch)

---

## Binary question

Does full INTR-block cold-reset in `acp70_enable_interrupts()` (ENB=0, CNTL0/1=0, STAT W1C, flush, reprogram) restore Linux IRQ delivery after s2idle?

**Answer: NO.**

---

## Witnesses (resume=1)

| Witness | Result |
|---------|--------|
| `PHASE9 falsify patch=B` post-reset MMIO | **all zero** (reset ran) |
| `pm_resume_done stat1=0x0` | ✓ |
| `post_delay STAT1=0x4 STAT&mask=0x4` | ✓ @ ~51 ms |
| `irq_handler_enter resume≥1` | **0** |
| `handler_since_pm` | **0** |
| `/proc/interrupts` IRQ 160 (s2idle window) | **since_pm=0** (authoritative) |
| `/proc/interrupts` compare script | 223→327 sum delta=208 — **contaminated** (pre taken ~43 s before suspend; DMA bursts @ 18:17:36) |
| RT721 | **-110** @ +5265 ms |

---

## Closed hypothesis

**“Incomplete INTR block re-arm (latent CNTL/STAT state) prevents edge delivery after resume.”**

Cold-reset proves MMIO can be brought to a known-zero state and reprogrammed; the **0→4 @ ~51 ms** event still does not reach `acp63_irq_handler`. Same signature as baseline and Patch A fail.

---

## Outcome classification

**Outcome 2 (FAIL same)** per [0009-falsification-matrix.md](0009-falsification-matrix.md): ACP MMIO re-arm path exhausted for this failure mode.

---

## Updated hypothesis tree

| Hypothesis | Status |
|------------|--------|
| STAT pending before unmask (level-trap) | ❌ Patch A |
| Incomplete INTR block re-arm (CNTL/STAT) | ❌ **Patch B** |
| IRQ not delivered to kernel after resume | ✅ **best explanation** |
| Linux IRQ desc masked / not re-enabled | **open — Patch E** |
| PCI bus master lost on resume | **open — Patch D** |
| ACP70 bridge / firmware | **open — after E/D** |

---

## Next

1. **Patch E** — `enable_irq(pci->irq)` at start of `snd_acp_resume()` (`build-phase8-falsify.sh --patch E`; strip PHASE9 / restore base first).
2. **Patch D** — `pci_set_master()` if E inconclusive.
3. No further `ps-common.c` falsification unless E/D change the event signature.

---

## Related

| Doc | Role |
|-----|------|
| [0009-run-falsify-A-fail.md](0009-run-falsify-A-fail.md) | Prior falsification |
| [0009-falsification-matrix.md](0009-falsification-matrix.md) | Protocol |
| [ACP-CROSS-VERSION-PM.md](../ACP-CROSS-VERSION-PM.md) | Cross-gen PM audit |
