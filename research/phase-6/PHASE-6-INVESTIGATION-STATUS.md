# Phase 6 investigation status (ACP70 / PX13)

English (canonical). Last updated: 2026-07-10 (run **0015**).

**Delimitation:** FAIL path **complete** (run 0015). **Explanation:** open — PASS contrast or AMD input.

| Doc | Role |
|-----|------|
| [KNOWN-FACTS.md](KNOWN-FACTS.md) | Demonstrated vs not demonstrated |
| [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md) | **Submit-ready draft** (usable before PASS) |
| [UPSTREAM-STRATEGY.md](UPSTREAM-STRATEGY.md) | **If PASS never appears** — scenarios 2/3, bounded hunt |
| [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md) | Golden diff + capture procedure |

---

## Phase shift

| Stage | Focus |
|-------|--------|
| Early Phase 6 | **Delimitation** — where does resume break? |
| Runs 0013–0015 | Software path, registers, kicks — **closed on FAIL** |
| **Now** | Phase 6 **observation closed** → [Phase 7 experiments](../phase-7/INDEX.md) |

The project is no longer *"why RT721 times out."* That is answered. RT721 waits because nothing upstream signals `initialization_complete()`.

---

## Demonstrated on FAIL (0015, `resume=1`)

```text
manager_reset → clear_slave_status → init/enable manager (ret=0)
  → irq_enabled → block programmed → frameshape → D0 (ret=0)
  → STAT=0 (post-enable, post-bringup, post-D0)
  → no handler in ~5 s → no re-enumeration → RT721 -110
```

**Conservative claim:** no pending interrupt visible on instrumented reads; no handler in wait window. **Not:** hardware never fires.

---

## Frozen

- RT721 / TAS2783 / `bus.c` instrumentation — closed
- AMD patches 0008+ horizontal traces — **no default**; see [UPSTREAM-CONTRAST.md](UPSTREAM-CONTRAST.md)
- Phase 5 codec patches, PipeWire, px13-rebind — out of scope

**Installed trace (keep):** 0003–0007 for PASS capture only.

---

## Key runs

| Run | Note |
|-----|------|
| 0013 | STAT=0, S1; S2 ruled out |
| 0014 | Block snapshot (0006) |
| **0015** | **Full kick sequence `ret=0`; STAT=0 post-D0** — strongest FAIL |

---

## Exit criteria

- [x] Observable break identified (STAT=0 + no handler)
- [x] S2 ruled out (0013)
- [x] Block programmed on FAIL (0014)
- [x] Software kick sequence complete on FAIL (0015)
- [x] Instrumentation freeze + binary-question policy documented
- [x] Upstream report draft (FAIL-only, conservative wording)
- [x] Upstream report draft (scenario 2/3 submittable)
- [ ] Optional: bounded PASS hunt (diminishing returns if N/N identical)
- [x] Handoff to [Phase 7 — bring-up experiments](../phase-7/INDEX.md)

---

## Commands (PASS hunt)

```bash
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-reboot --notes run-NN-attempt
systemctl suspend
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-suspend
```

Log: `/home/rutrus/snd_repair/validation/phase6-hunt-log.csv`

See [UPSTREAM-STRATEGY.md](UPSTREAM-STRATEGY.md). If audio works but `sm` shows FAIL-1, treat as valuable data — audio PASS ≠ kernel witness PASS (FACT 9).
