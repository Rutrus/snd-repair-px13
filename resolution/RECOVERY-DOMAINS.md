# Recovery domains — what each action can restore

English (canonical). Not all recoveries act on the same **domain**. PASS/FAIL on one domain does not invalidate another.

---

## Domains

| Domain | Recovery | Restores | Closed? |
|--------|----------|----------|---------|
| **Userspace** | R01 PipeWire | Sink routing | — |
| **ALSA reload** | R02 | PCM reopen | — |
| **Manager** | R04 platform unbind+bind | SDW enumeration | **CLOSED** (E04) |
| **Module** | R06 | Driver reload | — |
| **Runtime PM** | R09 PCI runtime_suspend/resume | PM idle path | **open** (retest) |
| **PCI probe** | R07 unbind+bind | Full PCI reprobe | **CLOSED** (E07 / C02 RUN-09) |
| **PCI re-enum** | R08 remove+rescan | Plug-level re-init | explored (ambiguous) |
| **ACPI/FW** | FW01 | Firmware path | open |

---

## E04 conclusion (L2 CLOSED)

Not *"R04 fails."* Stronger:

> **Manager remove → probe is insufficient to rebuild S2→S3.**

Evidence (VALID S2 witness):

| Step | Result |
|------|--------|
| unbind | ✓ platform gone |
| bind + probe | ✓ platform back |
| RT721 | ✓ **ATTACHED** |
| ALSA playback | ✗ still broken |

**Before:** `manager resume ≠ probe`  
**After:** `manager probe == sufficient to enumerate` · `manager probe != sufficient for audio`

The lost state is **not exclusively in the manager**.

---

## Layer probability (informal, post-E04)

| Layer | Before | After E04 |
|-------|--------|-------------|
| L2 Manager | ~30% | **~10%** |
| L4 PCI/PM | ~45% | **~55%** |
| FW/ACPI | ~25% | **~35%** |

Do **not** revisit R04 unless new evidence.

### PCI probe domain (E07 / C02 KILLED — RUN-09)

> **PCI unbind+bind is insufficient to rebuild S2→S3.**

| Field | Before → After |
|-------|----------------|
| runtime_pm | active/usage=0 → unchanged |
| PMCSR | D0 → D0 |
| PCI_STATUS | 0x0006 intx=0 → unchanged |
| ALSA | fail → fail |

Do **not** revisit R07 unless new evidence. E08 (remove+rescan) is same class — deprioritized.

### Runtime PM domain (E09)

**BLOCKED** — transition never executed (`runtime_suspend` unreachable). E07 explores PCI in parallel; E09 stays open.

Run inspector **I01** (read-only) in S2:

```bash
sudo ~/snd_repair/resolution/scripts/inspectors/I01-runtime-pm-blockers.sh
```

---

## Post-E04 graph

```text
              manager reprobe
                    │
                    ▼
           RT721 ATTACHED ────► enumeration OK
                    │
                    ├──────────────────┐
                    ▼                  │
             audio usable              │
                    ▲                  │
                    │                  │
                    └──── missing edge ─┘
```

Search moves **below enumeration** (IRQ delivery, PCI bridge, runtime PM, FW).

---

## Retest queue (VALID S2 required)

Prior E09/E07/E08 runs were **ambiguous** (no certified S2). Order after L2 close:

1. **E07** — PCI probe (VALID S2)
2. **I01** — who blocks runtime PM? (read-only, in S2)
3. E08 retest if needed

```bash
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E09 --from-s2
```

---

## Related

- [STATE-GRAPH.md](STATE-GRAPH.md)
- [experiments/E04-protocol.md](experiments/E04-protocol.md)
- [WITNESS-QUALITY.md](WITNESS-QUALITY.md)
