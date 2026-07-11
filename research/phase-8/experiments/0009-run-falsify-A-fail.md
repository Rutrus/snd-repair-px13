# Run p8-falsify-A-fail — Patch A falsified (STAT1 preclear before ENB)

English (canonical). **2026-07-11** · boot `d1b4fcdf` · Phase **8.2**

Snapshots:

- `validation/.state/irq-pre-suspend-20260711T180242.txt`
- `validation/.state/irq-post-resume-20260711T180506.txt`

Patch: [../proposed/0009a-stat1-preclear.patch](../proposed/0009a-stat1-preclear.patch)

---

## Binary question

Does explicit W1C clear of `ACP_SDW1_STAT` on `INTR_STAT1` **before** `acp70_enable_interrupts()` restore legacy IRQ delivery after s2idle?

**Answer: NO.**

---

## Witnesses (resume=1)

| Witness | Result |
|---------|--------|
| `PHASE9 falsify patch=A stat1_after=0x0` | Clear ran (STAT1 already 0) |
| `pm_resume_done stat1=0x0` | ✓ |
| `intr_stat_post_enable stat=0x0` | ✓ |
| `post_D0 STAT&mask=0x0` | ✓ |
| `post_delay STAT1=0x4 STAT&mask=0x4` | ✓ @ ~51 ms |
| `irq_handler_enter resume≥1` | **0** |
| `handler_since_pm` | **0** |
| `/proc/interrupts` IRQ 160 | sum **70→70 delta=0** |
| RT721 | **-110** |

---

## Closed hypothesis

**“STAT1 was pending (level-high) before interrupt unmask / enable — no new edge.”**

Logs already showed STAT1=0 through unmask and D0; Patch A **experimentally falsifies** the corrective (preclear before ENB does not fix delivery).

The failure mode is: **0→4 transition ~51 ms after D0, no Linux IRQ** — not stale level before mask.

---

## Updated hypothesis tree

| Hypothesis | Status |
|------------|--------|
| Manager SDW broken | ❌ 0006a |
| RT721 primary | ❌ |
| irq thread broken | ❌ 0006a |
| STAT never appears | ❌ 0006b |
| Handler ignores event | ❌ 8.1 |
| STAT pending before unmask (level-trap) | ❌ **Patch A** |
| IRQ not delivered to kernel after resume | ✅ **best explanation** |
| Incomplete INTR block re-arm (CNTL1/STAT1) | **open — Patch B** |
| Linux IRQ desc masked | **open — Patch E** |
| ACP70 bridge / firmware | **open — after B/D** |

---

## Next

1. **Patch B** — full CNTL1/STAT1 reset before reprogram (`build-phase8-falsify.sh --patch B`; revert patch A in tree first).
2. **Patch D** — `pci_set_master` (cheap falsification).
3. Code: [ACP-CROSS-VERSION-PM.md](../ACP-CROSS-VERSION-PM.md)

---

## Related

| Doc | Role |
|-----|------|
| [0009-falsification-matrix.md](0009-falsification-matrix.md) | Protocol |
| [INVESTIGATOR-QA.md](../INVESTIGATOR-QA.md) | Pre-unmask timeline |
