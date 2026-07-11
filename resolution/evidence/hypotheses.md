# Hypotheses — narrative index

Accepted model: [accepted_models.yaml](accepted_models.yaml) · Assumptions: [assumptions.yaml](assumptions.yaml)

---

## M_INTX_CORE (accepted model — not certainty)

**Observations:** I001–I004 (STAT1, intx_status, handler)

**Inference:** loss of **observability** at PCI config — not proven internal mechanism

**Confidence:** 0.85 (calibrated)

---

## H_INTX_CAUSE competitors

| ID | Priority | Notes |
|----|----------|-------|
| **H_CAUSE_CLK** (Alt A) | high | Clock/power gated routing |
| **H_CAUSE_FABRIC** (Alt D) | high | Fabric registration lost on resume |
| H_CAUSE_TRANSIENT (Alt B) | **low** | 1ms poll insufficient; deprioritized |
| H_DMA | low | 0.15 |

---

## C01 parallel tracks

1. [C01-upstream-handoff.md](../experiments/C01-upstream-handoff.md) — **open maintainer now**
2. [C01-falsification-protocol.md](../experiments/C01-falsification-protocol.md) — falsify only

---

## Killed

H_PROBE_PCI (C02 RUN-09)
