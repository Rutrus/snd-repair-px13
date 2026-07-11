# Edge types — four action families

English (canonical). Edges (E04, E07, E09…) map to recovery scripts (R04, R07, R09…). **Type** describes what the action does to system state — not PASS/FAIL.

---

## Types

| Type | Question | Destroys resource? | Example |
|------|----------|-------------------|---------|
| **Recover** | Can we restore without teardown? | No | E04 / R04 — manager platform rebind |
| **Replay** | Does repeating a PM sequence fix it? | No | E09 / R09 — runtime suspend/resume cycle |
| **Reprobe** | Does full driver reprobe rebuild state? | Yes (PCI unbind) | E07 / R07 — PCI unbind+bind |
| **Reconstruct** | Can we replicate boot initialization? | Varies | Future — boot sequence replay (R002) |

E07 is **Reprobe**, not Recover: `S2 → destroy PCI function → recreate PCI → S?`

---

## Mapping (current queue)

| Edge | Recovery | Type | Domain |
|------|----------|------|--------|
| E04 | R04 | **Recover** | manager (L2 closed) |
| E09 | R09 | **Replay** | runtime_pm (BLOCKED) |
| E07 | R07 | **Reprobe** | pci_probe (active) |
| E08 | R08 | **Reprobe** | pci_reenum (remove+rescan) |
| — | R002 (planned) | **Reconstruct** | boot replay |

---

## E07 (Reprobe) goal

Primary execution: ALSA PASS/FAIL.

Knowledge goal: **differential snapshot** (what changed pre→post reprobe). See [experiments/E07-protocol.md](experiments/E07-protocol.md).

Updates facts `O_E07_DIFF` and may revise `F004`–`F005`, `F012`, `O_IOMMU`.

---

## Related

- [EDGE-FRAMEWORK.md](EDGE-FRAMEWORK.md) — witness gate, confidence
- [RECOVERY-DOMAINS.md](RECOVERY-DOMAINS.md) — L2/L4 closure
- [evidence/facts.yaml](evidence/facts.yaml)
