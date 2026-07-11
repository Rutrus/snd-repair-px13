# E07 run protocol — PCI probe domain (differential snapshot)

English (canonical). After I01 closed, I02 open. Facts: [../evidence/facts.yaml](../evidence/facts.yaml)

**Edge type:** Reprobe ([EDGE-TYPES.md](../EDGE-TYPES.md))

---

## Primary question

> **What changes exactly between the instant immediately before E07 and immediately after — even if ALSA still fails?**

ALSA PASS/FAIL remains the edge execution verdict. Knowledge gain = **differential snapshot**.

---

## Snapshot fields (before → after)

| Field | Source |
|-------|--------|
| `runtime_status` / `runtime_usage` | sysfs `power/` |
| PCI D-state | `setpci` PMCSR |
| `PCI_STATUS` + INTx bit | `setpci` |
| PHASE10 `post_delay` | kernel journal (latest) |
| IOMMU faults | count since R07 action |

Report line: `R07 Differential: pm: … → … | dstate: … | status: … | iommu_since=N`

---

## Sequence

```bash
# 1. I02 — faults + Type A/B/C vs STAT1
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh since-last-resume

# 2. Certified S2 + R07 differential
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E07 --from-s2

# 3. I02 again — timing class + parsed fields
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh
```

Update [../evidence/facts.yaml](../evidence/facts.yaml) observation `O_E07_DIFF` and related facts after run.

---

## Correlation triangle (if E07 FAIL)

| Fact | Inspector |
|------|-----------|
| `STAT1=0x4` + `intx_status=0` | 0010 / PHASE10 |
| `active` + `usage=0` | I01 |
| IO_PAGE_FAULT Type A/B/C + fields | I02 |

Interpret via [../evidence/hypotheses.md](../evidence/hypotheses.md) — H-INTx vs H-DMA competitor.

**Discipline:** IO_PAGE_FAULT is observability until timing is stable across runs.
