# C01 — Maintainer handoff (do not wait for perfect explanation)

English (canonical). **Open now** — parallel with falsification-only experiments.

Evidence pack:

- [../evidence/accepted_models.yaml](../evidence/accepted_models.yaml) — observation vs inference
- [../evidence/assumptions.yaml](../evidence/assumptions.yaml) — implicit assumptions
- [../negative/rejected-fixes.yaml](../negative/rejected-fixes.yaml) — patches A–E, RF001, RF004
- [../../research/phase-8/UPSTREAM-REPORT.md](../../research/phase-8/UPSTREAM-REPORT.md) — submittable facts

---

## What to send (facts first)

**Observations (not inference):**

1. Resume: `STAT1=0x4` @ ~51ms post-D0 (0010/0006b)
2. Same window: `PCI_STATUS.Interrupt Status=0`, `INTX_DISABLE=0`
3. Boot contrast: same `STAT1=0x4` → `intx_status=1` → handler runs
4. `handler_since_pm=0`; `/proc/interrupts` delta=0
5. Negative: Patches A, B, E fail; manager reprobe (E04) and PCI reprobe (E07/C02) fail

**Inference (one sentence, calibrated):**

> We observe loss of PCI interrupt status assertion when STAT1 is latched post-resume; we do not claim to know the internal ACP mechanism.

---

## Questions maintainers can answer quickly

| # | Question |
|---|----------|
| Q1 | Undocumented register between `ACP_EXTERNAL_INTR_STAT1` and PCI INTx? |
| Q2 | Mandatory re-arm sequence after s2idle (register X)? |
| Q3 | Reset distinct from INTR block cold-reset (Patch B)? |
| Q4 | Known ACP70 erratum for SoundWire resume / INTx fabric? |
| Q5 | Does clock/power domain gating explain STAT1 alive but PCI status dead? |
| Q6 | Is interrupt fabric **registration** lost on resume (Alt D)? |

---

## What NOT to lead with

- "Propagation is broken" (too strong — use loss of observability)
- Alt B transient bit (deprioritized — see hypotheses.yaml)
- New exploratory driver patches without falsification target

---

## Risk to avoid

Converting M_INTX_CORE from **accepted model** into **certainty** before maintainer input.

---

## Related

- [C01-falsification-protocol.md](C01-falsification-protocol.md)
- [../campaigns/C01-intx-bridge/campaign.yaml](../campaigns/C01-intx-bridge/campaign.yaml)
