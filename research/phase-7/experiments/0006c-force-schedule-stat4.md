# Experiment 0006c — force schedule on STAT=0x4 (deliberate hack)

English (canonical). **Falsification only — not a fix candidate.**

Run **only if:**

- [0006a](0006a-validate-manager-mask.md) is **negative** (`stat & manager_mask` never set, manual schedule never triggered), and
- [0006b](0006b-stat-decode.md) confirms **`0x4` persists** on the relevant STAT register.

---

## Question

> If we **artificially** call `schedule_work(&amd_manager->amd_sdw_irq_thread)` when `STAT == 0x4` (ignoring manager mask), can the driver progress to ATTACHED / completion?

Separates:

- **Delivery hypothesis:** mask bit never hits; `0x4` is irrelevant noise.
- **Wrong-bit hypothesis:** `0x4` carries useful state but handler listens to a different bit.
- **Empty-thread hypothesis:** thread runs but ping/status path is still empty.

---

## Intervention (intentionally wrong for production)

```c
stat = readl(... ACP_EXTERNAL_INTR_STAT(instance) ...);
if (stat == 0x4)   /* or (stat & 0x4) — document exact test */
    schedule_work(&amd_manager->amd_sdw_irq_thread);
```

**Do not** combine with 0006a in the same run without a boot param to select mode.

Suggested boot param: `phase7_force_stat4=1` (module param, default 0).

---

## Outcomes

| Outcome | Interpretation |
|---------|----------------|
| ATTACHED / completion | Thread can progress when woken on this STAT pattern — **IRQ routing / bit selection** suspect |
| Thread runs (`irq_thread_enter`) but no ATTACHED | `0x4` insufficient — still missing ping/state-change |
| Nothing | `0x4` is not the event the thread expects |

---

## Ethics / upstream

Label clearly in patch subject: `PHASE7 falsification: force irq_thread on stat 0x4`. Never merge to production without 0006a/0006b conclusions.

Patch: `research/phase-7/proposed/0006c-force-schedule-stat4.patch` (TBD)
