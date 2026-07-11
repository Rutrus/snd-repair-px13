# ACP cross-version PM — interrupt enable/disable sequence

English (canonical). Static comparison across AMD ACP drivers in `linux-source-7.0.0/sound/soc/amd/`. **Sequence differences**, not style.

**Goal:** Find a disable→enable pattern present on older ACP ports that ACP70 resume may omit. Informs Patch **B** and upstream question.

---

## Summary

| Generation | Driver tree | `disable_interrupts` clears | `enable_interrupts` | STAT1 / CNTL1 on disable |
|------------|-------------|------------------------------|---------------------|--------------------------|
| ACP2.x legacy | `acp/acp-legacy-common.c` | STAT (per bank) | ENB + CNTL \|= error | Single STAT bank |
| ACP5x | `vangogh/pci-acp5x.c` | STAT0, CNTL0, ENB | ENB only | **No STAT1** (no SDW1 block) |
| ACP6x (YC) | `yc/pci-acp6x.c` | STAT0, CNTL0, ENB | ENB only | **No STAT1** |
| ACP6.3 | `ps/ps-common.c` `acp63_*` | STAT0, CNTL0, ENB | ENB + CNTL0 error | **No STAT1, no CNTL1** |
| ACP7.0 | `ps/ps-common.c` `acp70_*` | **Same as 63** | + host_wake **CNTL1** | **No STAT1, no CNTL1 zero** |

**Finding:** None of the in-tree AMD paths clear **`ACP_EXTERNAL_INTR_STAT1`** or zero **`ACP_EXTERNAL_INTR_CNTL1`** on disable. ACP70 adds CNTL1 writes on enable (host wake) but **inherits the same STAT0-only disable** as ACP63.

**Not found:** `disable_irq()` / `enable_irq()` around ACP MMIO enable in any of these drivers — Linux IRQ API is probe-only in `ps/pci-ps.c`.

---

## ACP6.3 vs ACP7.0 (`ps-common.c`) — only IRQ-relevant diffs

| Step | `acp63_disable_interrupts` | `acp70_disable_interrupts` |
|------|------------------------------|----------------------------|
| STAT0 clear | `writel(ALL_1s, INTR_STAT)` | same |
| STAT1 clear | **none** | **none** |
| CNTL0 | `0` | `0` |
| CNTL1 | **unchanged** | **unchanged** |
| ENB | `0` | `0` |

| Step | `acp63_enable_interrupts` | `acp70_enable_interrupts` |
|------|---------------------------|---------------------------|
| ENB | `1` | `1` |
| CNTL0 | `ACP_ERROR_IRQ` | same |
| CNTL1 | **none** | optional `\|= 0xC00000` host wake |
| PME | in init: **no** | `writel(PME_EN, 1)` after enable |

| Step | `acp63_init` order | `acp70_init` order |
|------|-------------------|-------------------|
| After reset | enable_irq → ZSC=0 | ZSC=0 → enable_irq → PME=1 |

| Step | `acp63_deinit` tail | `acp70_deinit` tail |
|------|---------------------|---------------------|
| After reset | `CONTROL=0`, ZSC=1 | **ZSC=1 only** (no CONTROL=0) |

**Resume path:** both use same `snd_acp{63,70}_resume` pattern (`acp_hw_init` full path or fast ZSC/PME). **No generation adds STAT1 clear on resume.**

---

## Older platforms (reference)

### ACP5x (`pci-acp5x.c`)

```text
disable: STAT0 clear, CNTL0=0, ENB=0
enable:  ENB=1 only
```

### ACP6x YC (`pci-acp6x.c`)

Same pattern as ACP5x.

### ACP legacy (`acp-legacy-common.c`)

```text
disable: STAT clear (one bank), ENB=0  (CNTL not zeroed in disable)
enable:  ENB=1, CNTL |= error mask
```

Legacy **does not** zero CNTL on disable either; uses read-modify-write on enable.

---

## Implication for Patch B

Patch B tests what **no upstream generation does in one place today:** explicit **CNTL1=0 + STAT1 W1C all** immediately before reprogramming ENB/CNTL0/host_wake.

If B **passes:** gap is “stale CNTL1 / STAT1 across deinit→init without full block reset.”  
If B **fails:** symmetric with A — software block replay insufficient → **bridge / Linux IRQ / firmware** (patches D, E, upstream).

---

## Implication for upstream

> ACP63 and ACP70 share `disable_interrupts()` that never touches STAT1/CNTL1. ACP70 adds CNTL1 host-wake on enable. On PX13, after s2idle, STAT1 shows a fresh 0→4 transition with no legacy IRQ to `acp63_irq_handler()`, while cold boot delivers. Is there an ACP70-specific INTR block re-arm sequence not present in `acp70_enable_interrupts()`?

---

## Errata search (2026-07-11)

No public hit found in quick search for “ACP70 s2idle interrupt” / “ACP70 legacy IRQ resume” in open AMD or kernel bugzilla summaries. **Maintainer / AMD NDA channel** is the realistic path if patches B and D fail.

Track locally if documents appear; do not claim erratum without source.

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0009-run-falsify-A-fail.md](experiments/0009-run-falsify-A-fail.md) | Patch A result |
| [experiments/0009-falsification-matrix.md](experiments/0009-falsification-matrix.md) | Patch B next |
| [ACP-BOOT-VS-RESUME-CALLS.md](ACP-BOOT-VS-RESUME-CALLS.md) | Call matrix |
