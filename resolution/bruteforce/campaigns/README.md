# Bruteforce campaigns

English (canonical). Each campaign is a **set of full sequences**, not isolated R0x steps.

## Validation (run before recovery)

| ID | Focus | Entry |
|----|-------|-------|
| **V100** | Strategy validation | `run-bruteforce.sh --validate` |

Phases: `modules` · `pci` · `objects` · `unload` (V004 delta)

---

## Recovery

| ID | Focus | Strategies | Cost |
|----|-------|------------|------|
| **R100** | Software restart | S001, S002 | 1 |
| **R200** | Anchor module reload | S010 | 3 |
| **R300** | PCI reprobe + reload | S020 | 5 |
| **R400** | Runtime PM + modules | S030 | 4 |
| **R500** | PCI FLR / reprobe | S040 | 5 |
| **R550** | PCI remove + rescan | S070 | 6 |
| **R600** | Recover + 2nd suspend | S060 | 6 |
| **R700** | Runtime PM (not power/state) | S050 | 4 |

**Default run order:** R200 → R300 → R550 → R500 → R100 → R400 → R700 → R600

---

## Success criterion

**PASS** = `witness_playback_alsa` (plughw) after strategy, from certified S2.

A FAIL after a broken strategy (e.g. pci_reset after unload) is **invalid evidence** — fix validation first.

---

## PX13 module model (7.0.0-27)

- **Anchor:** `snd_pci_ps` — `modprobe -r -va` / `modprobe -va` handles dependency order
- **Not modules:** `snd_soc_amd_ps`, `snd_soc_amd_acp_mach` (use `snd_acp_sdw_legacy_mach` etc.)
- **PCI reprobe:** must run while driver sysfs exists (before anchor unload)
