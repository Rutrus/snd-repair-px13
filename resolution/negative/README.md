# Negative knowledge — rejected interventions

English (canonical). Source of truth: [rejected-fixes.yaml](rejected-fixes.yaml)

**Purpose:** Prevent re-proposing disproven patches or recoveries months later.

---

## Patches (research phase 8)

| ID | Name | Result |
|----|------|--------|
| PF001 | STAT1 preclear (A) | FAIL — identical signature |
| PF002 | INTR cold-reset (B) | FAIL |
| PF003 | PME before enable (C) | FAIL |
| PF004 | pci_set_master (D) | FAIL |
| PF005 | Linux enable_irq (E) | FAIL |

---

## Recoveries (resolution)

| ID | Name | Result |
|----|------|--------|
| RF001 | Manager reprobe E04 | Informative FAIL — L2 closed |
| RF002 | Runtime PM E09 | BLOCKED — parked C04 |
| RF003 | PipeWire R01 | Insufficient layer |
| **RF004** | **PCI reprobe E07** | **C02 KILLED RUN-09 — L4 closed** |

---

## Before proposing a new fix

1. Search `rejected-fixes.yaml`
2. Check [invariants.yaml](../evidence/invariants.yaml)
3. If same mechanism class → do not repeat without new evidence

---

## Related

- [../research/phase-8/STAT1-TO-PCI-BOUNDARY.md](../../research/phase-8/STAT1-TO-PCI-BOUNDARY.md)
- [../EXIT-CRITERIA.md](../EXIT-CRITERIA.md)
