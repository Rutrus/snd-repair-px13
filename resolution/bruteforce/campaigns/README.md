# Bruteforce campaigns

English (canonical). Each campaign is a **set of full sequences**, not isolated R0x steps.

| ID | Focus | Strategies | Cost |
|----|-------|------------|------|
| **R100** | Software restart | S001, S002 | 1 |
| **R200** | Module stack reload | S010 | 3 |
| **R300** | Nuclear sequences | S020 | 5 |
| **R400** | Runtime PM + modules | S030 | 4 |
| **R500** | PCI FLR / hard reset | S040 | 5 |
| **R600** | Recover + 2nd suspend | S060 | 6 |
| **R700** | ACPI D3/D0 | S050 | 4 |

**Default run order:** R200 → R300 → R500 → R100 → R400 → R700 → R600

---

## Success criterion

**PASS** = `witness_playback_alsa` (plughw) after strategy, from certified S2.

No hypothesis update required — log sequence ID in TRACKER.

---

## Not tried yet as full sequences

- unload **all** audio modules + PCI unbind + bind + full reload + udev + alsactl (S020)
- runtime PM with **zero** modules loaded (S030)
- FLR when sysfs `reset` writable (S040)

These are the highest-value gaps vs prior single-action edges (E04/E07/R06).
