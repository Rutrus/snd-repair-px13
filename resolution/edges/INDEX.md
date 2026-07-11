# Edge catalog

English (canonical). Framework v2: **NEW → PROMISING → STABLE**

State: [state.json](state.json) · Rules: [../EDGE-FRAMEWORK.md](../EDGE-FRAMEWORK.md)

---

## Exploration queue

**Phase:** `exploration` — L2 **CLOSED** · retest queue active.

| Order | Edge | Domain | Status | Conf. |
|-------|------|--------|--------|-------|
| — | S2 gate | oracle | PASSED W2 | — |
**Runtime PM domain: BLOCKED** (RUN-07) — `runtime_suspend` unreachable in S2. Not a FAIL on the hypothesis.

| Order | Edge | Domain | Status |
|-------|------|--------|--------|
| **1** | [E07](E07.md) | pci_probe | **NEXT** |
| 2 | [E08](E08.md) | pci_reenum | retest |
| — | [E09](E09.md) | runtime_pm | **BLOCKED** |
| — | [E04](E04.md) | manager | **L2 CLOSED** |

```bash
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E07 --from-s2
```

Domains: [RECOVERY-DOMAINS.md](../RECOVERY-DOMAINS.md)
