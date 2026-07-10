# Phase 6 investigation status (ACP70 / PX13)

English (canonical). Last updated: 2026-07-10 (run **0013**).

**Progress:** ~95%. **Phase shift:** from locating the first break → explaining why ACP produces **no first event** after `manager_reset`.

**Facts:** [KNOWN-FACTS.md](KNOWN-FACTS.md) · **Next ACP-only:** [proposed/NEXT-ACP-STAT-ZERO.md](proposed/NEXT-ACP-STAT-ZERO.md)

---

## Break chain (run 0013)

```text
manager_reset
      ↓
irq_enabled
      ↓
ACP_EXTERNAL_INTR_STAT = 0x0
      ↓
(no irq_handler_enter / irq_thread_enter)
      ↓
no completion
      ↓
RT721 timeout (-110)
```

SDW protocol layer **never starts** on this path.

---

## Ruled out / open (maintainer-safe)

| Item | Run 0013 |
|------|----------|
| S2 (stat≠0, no handler) | **Ruled out** |
| IRQ routing as sole story | **Unlikely** on 0013 |
| Codec / TAS2783 first | **Ruled out** (FACT 5) |
| Why STAT=0 | **Open** — HW never fired vs late event vs missing kick |

---

## Hypotheses (post-0013)

| ID | ~% | Scope |
|----|---:|-------|
| **H-ACP-SEQ** | **85** | ACP manager / HW sequencing after `manager_reset` |
| **H-SDW** | 10 | SDW path after IRQ (not reached on FAIL) |
| **H-codec** | 5 | Witness only |

---

## Instrumentation

| Patch | Role | Status |
|-------|------|--------|
| 0003–0004 | resume=N, irq chain witnesses | Done |
| **0005** | S1/S2 bisect | Done — **S1 on 0013** |
| **0006** | Why STAT=0 (ACP regs / enable / kick) | Proposed |

**No more SoundWire instrumentation** until ACP first-event mechanism differs on PASS.

---

## Runs

| Run | Result |
|-----|--------|
| 0010, 0012 | Gap after `irq_enabled` |
| **0013** | **S1:** `stat=0x0`, no handler |

```bash
./scripts/phase6-experiment.sh sm 0013
```

---

## Exit criteria

- [x] S1/S2 bisect (0013)
- [x] FACT 7 chain documented
- [ ] Optional: second 0005 FAIL for reproducibility
- [ ] PASS: `STAT≠0` → handler → completion (upstream gold)
- [ ] 0006: why STAT=0 on FAIL vs PASS

---

## Commands

```bash
./scripts/build-phase6-amd-trace.sh
./scripts/phase6-experiment.sh sm 0013
./scripts/phase6-experiment.sh tl 0013
```
