# Depth matrix — Cost × Knowledge

English (canonical). Prioritize by **Knowledge ÷ Cost**, not cost alone.

**Last updated:** 2026-07-11

---

## Scales

### Recovery Cost (1–8, lower = cheaper)

Practical price: depth + disruption + time.

### Knowledge Gain (1–5, higher = more informative)

| Score | Label | Meaning |
|-------|-------|---------|
| **1** | very low | Userspace only; unlikely to inform kernel fix |
| **2** | low | ALSA reopen; confirms stack layer |
| **3** | medium | Identifies subsystem (manager vs PCI) |
| **4** | high | Separates probe vs resume, or PM path |
| **5** | very high | Separates system PM vs runtime PM, or proves hardware recoverable |

### Priority score

`Knowledge Gain ÷ Recovery Cost` — higher = run sooner when **exploring** (not when executing cheap ladder for production workaround).

---

## Recovery transitions (binary)

**Run order for exploration:** R09 → R07 → R08 → R04 → R06 → R01…

| ID | Transition added | Layer | Cost | Know. | **K/C** | PASS | Script |
|----|------------------|-------|------|-------|---------|------|--------|
| **R09** | runtime_suspend → runtime_resume | L4 | 3 | **5** | **1.67** | `?` | [R09](scripts/recovery/R09-runtime-pm-cycle.sh) |
| **R07** | PCI driver unbind → probe | L4 | 4 | **5** | **1.25** | `?` | [R07](scripts/recovery/R07-rebind-pci.sh) |
| **R08** | PCI remove → rescan → probe | L4 | 5 | 3 | 0.60 | `?` | [R08](scripts/recovery/R08-remove-rescan-pci.sh) |
| **R04** | manager unbind → bind (probe) | L2 | 2 | 3 | 1.50 | `?` | [R04](scripts/recovery/R04-rebind-manager.sh) |
| **R06** | module reload → re-probe | L3 | 4 | 3 | 0.75 | `?` | [R06](scripts/recovery/R06-reload-acp-module.sh) |
| **R03** | RT721 unbind | L2 | 3 | 2 | 0.67 | `?` | [R03](scripts/recovery/R03-unbind-rt721.sh) |
| **R05** | SDW bus rescan | L2 | 3 | 2 | 0.67 | `?` | [R05](scripts/recovery/R05-sdw-rescan.sh) |
| **R10** | second system suspend | L7 | 3 | 2 | 0.67 | `?` | [R10](scripts/recovery/R10-secondary-suspend.sh) |
| **R02** | ALSA reopen | L1 | 2 | 2 | 1.00 | `?` | [R02](scripts/recovery/R02-alsa-reload.sh) |
| **R01** | PipeWire restart | L0 | 1 | 1 | 1.00 | `?` | [R01](scripts/recovery/R01-restart-pipewire.sh) |
| **R11** | ACPI D3→D0 | L5 | 6 | 4 | 0.67 | `?` | [acpi.md](reverse-engineering/acpi.md) |
| **R12** | platform reset | L6 | 8 | 4 | 0.50 | `?` | — |

---

## Exploration priority (Knowledge/Cost)

| Rank | ID | Why |
|------|-----|-----|
| **1** | **R09** | Highest K/C; system PM vs runtime PM |
| **2** | R04 | Manager probe vs resume |
| **3** | R07 | PCI probe vs pm_resume |
| **4** | R08 | Re-enumeration (lower knowledge if R07 already PASS) |
| **5** | firmware/ | If R09+R07+R08 all FAIL — [firmware/README.md](firmware/README.md) |

---

## Production ladder (cheapest workaround)

Once exploring, optimize for **lowest Cost** among stable PASS edges:

```text
R01(1) → R02(2) → R04(2) → R09(3) → R07(4) → R08(5)
```

Two different orderings — **explore** by K/C, **ship** by Cost.

---

## Best edge found

| Metric | Value |
|--------|-------|
| Best exploration hit | — |
| Cheapest stable PASS (Cost) | — |
| Knowledge Gain of best edge | — |
| Missing transition identified | — |
| Research question unlocked | — |

See [STATE-GRAPH.md](STATE-GRAPH.md) · [TRACKER.md](TRACKER.md)
