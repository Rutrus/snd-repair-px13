# Experiment 0008 — IRQ boundary trace (Phase 8.1)

English (canonical). **Observation only** — no behaviour change beyond counters and `printk`.

**Goal (8.1):** Distinguish *handler never runs* from *IRQ never reaches Linux* using independent witnesses.

---

## Binary question

> After s2idle resume, while the SoundWire manager reads `STAT1 & mask = 0x4`, does **`acp63_irq_handler()` execute zero times**, and does the **Linux IRQ counter** for `ACP_PCI_IRQ` stay unchanged in the same boot?

---

## Probes (0008.1)

| Id | Log / metric | Answers |
|----|----------------|---------|
| **0008.1** | `pm_suspend_enter` | Suspend path entered; resets `since_pm` counter |
| **0008.2** | `irq_stats` @ `pm_resume_done` | `handler_total`, `handler_since_pm`, `last_stat0/1` |
| **0008.3** | `irq_handler_enter` (0007) | Handler entered at all? |
| **0008.4** | `/proc/interrupts` pre/post | Kernel IRQ layer count delta (same boot) |

Patch: `0008-irq-boundary-trace.patch` on Phase 6 + **0007 pci-ps** (no 0006b / correlate required).

---

## Build

```bash
./scripts/build-phase8.sh --experiment irq-boundary-trace
sudo reboot
```

Regenerate: `./scripts/regenerate-phase8-0008.sh` (requires 0007 on `pci-ps.c`).

---

## Run protocol (N cycles, same boot)

```bash
./scripts/phase6-hunt.sh post-reboot --notes p8-irq-boundary-1

# cycle 1
./scripts/phase8-irq-snapshot.sh pre-suspend
systemctl suspend
./scripts/phase8-irq-snapshot.sh post-resume
./scripts/phase6-hunt.sh post-suspend --notes p8-boundary-c1

# optional cycles 2–3 (reboot between sessions if resume_n>1 policy)
journalctl -k -b 0 | grep -E 'PHASE8 ctx=acp fn='
journalctl -k -b 0 | grep 'PHASE7 ctx=acp fn=irq_handler_enter' | tail -5
./scripts/phase8-irq-snapshot.sh compare
```

---

## Decision (8.1 closure)

| Evidence | Interpretation |
|----------|----------------|
| `handler_since_pm=0` + no `irq_handler_enter` @ resume≥1 + `/proc/interrupts` unchanged in resume window | **Fact:** handler not invoked; strengthens delivery gap before/at Linux IRQ |
| `/proc/interrupts` increments, `handler_since_pm=0` | IRQ delivered but not to our handler — investigate shared IRQ / wrong handler |
| `handler_since_pm>0` on resume | Contradicts Phase 7 correlate — re-open boundary |

---

## Out of scope

- Phase 7 interventions (0006a), delays (0005), correlate (0007+0006b)
- SoundWire manager patches

---

## Status

**8.1 closed** — milestone run [0008-run-boundary-c1.md](0008-run-boundary-c1.md) (2026-07-11).

---

## Relation

| Phase | Role |
|-------|------|
| [Phase 7 correlate](../phase-7/experiments/0007-run-correlate-d50.md) | STAT pending + no handler log |
| **0008 (this)** | Independent handler counter + `/proc/interrupts` |
| [0008-run-boundary-c1.md](0008-run-boundary-c1.md) | **Milestone** — three witnesses |
| [8.2 + 8.3 ACP-IRQ-FLOW](../ACP-IRQ-FLOW.md) | Register ownership + last-write audit |
