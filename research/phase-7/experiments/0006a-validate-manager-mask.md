# Experiment 0006a — validate manager mask (manual irq_thread)

English (canonical). **NOT a fix** — falsify whether manually scheduling `amd_sdw_irq_thread` when `STAT(instance) & manager_mask != 0` unblocks enumeration.

**Prerequisite:** [0006b](0006b-stat-decode.md) confirmed Case 1 on PX13 (p7-0006b-d50):

| Snapshot | STAT1 | STAT&mask | handler |
|----------|-------|-----------|---------|
| `post_D0` | `0x0` | `0x0` | NO |
| `post_delay` (+50 ms) | `0x4` | `0x4` | NO |

Patch base: `0006b-stat-decode.patch` + `0006a-validate-manager-mask.patch`

---

## Question (single)

> If the driver runs the same work as a hardware IRQ when **`stat & manager_mask`** is set, does enumeration continue?

```c
if (stat & manager_mask)
    schedule_work(&amd_manager->amd_sdw_irq_thread);
```

Uses the driver's own mask — not magic `0x4`.

---

## Build

```bash
./scripts/build-phase7.sh --experiment validate-manager-mask --delay 50
./scripts/phase7-sweep-pre.sh 50
sudo reboot
```

Regenerate patches: `./scripts/regenerate-phase7-0006b.sh` then `./scripts/regenerate-phase7-0006a.sh`

---

## Run protocol

```bash
./scripts/phase6-hunt.sh post-reboot --notes p7-0006a-d50
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
journalctl -k -b 0 | grep -E 'manual_irq_schedule|irq_thread_enter|fn=completion|ATTACHED'
```

One suspend per boot (`resume_n=1`).

---

## Log probes (0006a)

```text
PHASE7 ctx=amd fn=manual_irq_schedule reason=STAT&mask when=post_delay link=%d resume=%d manager=%u stat=0x%x mask=0x%x hit=0x%x
PHASE7 ctx=amd fn=manual_irq_schedule skipped when=%s ... stat=0x%x mask=0x%x
```

Then Phase 6 chain: `irq_thread_enter`, `queue_work`, `ping_status`, bus `ATTACHED`, `completion`.

---

## Binary outcomes

| Outcome | Interpretation | Next |
|---------|----------------|------|
| **A** `schedule_work` → ATTACHED + completion + RT721 OK | IRQ **delivery** broken; HW/thread path OK | Upstream: MSI/routing/`pci-ps.c` |
| **B** `schedule_work` → thread runs, no ATTACHED | `STAT&mask` insufficient or empty ping path | Instrument `amd_sdw_irq_thread` / 0006c |
| skipped (stat&mask=0 at post_delay) | Observation regression — check delay_ms / decode | Re-run 0006b |
| PASS without manual schedule | Physical IRQ worked this run | Golden diff |

---

## Result (PX13, 2026-07-11) — **Outcome A**

Run [0006a-run-p7-d50.md](0006a-run-p7-d50.md) · notes `p7-0006a-d50` · boot `eebcde6d-…`

**Closed (positive falsification):** manual `schedule_work` at `post_delay` when `STAT&mask=0x4` → full enumeration, RT721 `ret=0`. No `irq_handler_enter`; yes `irq_thread_enter` at +51 ms.

**Conclusion:** ACP presents the manager IRQ bit; **`acp63_irq_handler` does not run**; thread path is healthy.

---

## Control

`phase7_delay_ms=0`: tries manual schedule once at `post_D0` only (expect **skipped** on FAIL-1).

---

## Relation to other experiments

| Exp | Role |
|-----|------|
| [0006b](0006b-stat-decode.md) | Observation — closed for PX13 Case 1 |
| **0006a** (this) | Intervention — `stat & mask` → `schedule_work` |
| [0006c](0006c-force-schedule-stat4.md) | Only if 0006a negative — force on raw `0x4` |
