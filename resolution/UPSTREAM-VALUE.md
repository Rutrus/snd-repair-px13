# Upstream value — resolution feeds research

English (canonical). Resolution is a **hypothesis generator**. Research re-activates at confidence ≥ **0.85** (PROMISING). Workarounds ship at **STABLE** (consolidation ×3).

**Gate:** [EDGE-FRAMEWORK.md](EDGE-FRAMEWORK.md) — exploration first, no 5/5 during mapping.

---

## Two values per edge

### 1. Practical

PX13 audio after suspend — hook, patch, script.

### 2. Scientific (narrows maintainer search)

From *"my laptop fails"* to *"fails until transition X"*:

- Hardware is **not** dead
- Firmware is **not** dead  
- A **reachable** good state exists

---

## Resolution → research handoff (post-C02, 2026-07-12)

| Outcome | Maintainer-facing claim |
|---------|-------------------------|
| **C02 KILLED** | PCI unbind+bind does **not** restore audio; relevant PCI/PM snapshot unchanged (I010) |
| **E04 FAIL** | Manager reprobe enumerates RT721; audio still broken (L2 closed) |
| **M_INTX_CORE** | **Observations:** STAT1=0x4, intx_status=0, handler=0. **Inference:** loss of observability before PCI config — not proven internal mechanism |
| **Next** | **Open maintainer thread now** — see [experiments/C01-upstream-handoff.md](experiments/C01-upstream-handoff.md) |

Do **not** wait for perfect explanation. Questions Q1–Q6 in handoff doc are answerable in minutes by AMD.

Parallel: [C01-falsification-protocol.md](experiments/C01-falsification-protocol.md) — falsify model only; no exploratory patches.

---

## Historical handoff table

| Stable edge | Research question (one only) | Do not |
|-------------|------------------------------|--------|
| **E09** Stable | What does **runtime PM** do that **system PM** does not? | Re-open IRQ archaeology broadly |
| ~~**E07** Stable~~ | ~~Diff probe vs pm_resume~~ | **CLOSED** — C02 KILLED; reprobe insufficient |
| **E04** Stable | Diff manager `probe()` vs `pm_resume()` | More STAT printk |
| **E08** Stable | What does re-enumeration reset that unbind+bind does not? | |
| **FW01** PASS | What does **Windows resume** program that Linux skips? | |
| All recovery FAIL | Boot sequence replay + ACPI/firmware | Phase 9 observation |

---

## Example upstream sentences

| Edge | Maintainer-facing claim |
|------|-------------------------|
| R09 | "After s2idle, `runtime_suspend/resume` restores audio; `snd_acp_resume` does not — system PM path incomplete" |
| R07 | "PCI driver re-probe recovers; `pm_resume` does not — missing probe-equivalent steps" |
| R04 | "Manager re-probe recovers; manager `pm_resume` does not" |
| 0006a | "Worker sufficiency proven; IRQ delivery is the missing transition" *(research, already filed)* |

---

## Workaround vs definitive fix

| Type | Example | Upstream role |
|------|---------|---------------|
| Workaround | runtime PM cycle in `systemd-sleep` | Proves recoverability; points to PM diff |
| Definitive | `pci_set_master()` in resume | Direct fix candidate |

Even ugly workarounds **reduce search space**.

---

## Discipline

```text
resolution finds edge
    ↓
freeze sequence in experiments/proposed/
    ↓
research: compare exactly two paths (e.g. runtime vs system PM)
    ↓
one patch or one upstream mail
```

**Avoid:** returning to open-ended investigation because resolution is "more fun."

---

## Related

| Doc | Role |
|-----|------|
| [STATE-GRAPH.md](STATE-GRAPH.md) | Missing transition model |
| [TRACKER.md](TRACKER.md) | Edge log |
| [firmware/README.md](firmware/README.md) | FW01+ if kernel recovery fails |
| [../research/frozen/upstream-proof/](../research/frozen/upstream-proof/) | Prior delimitation |
