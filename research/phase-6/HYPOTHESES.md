# Phase 6 hypotheses

Reorganized for **state transition analysis** — not firmware-first.

---

## H1 — RT721 resume incomplete (primary suspect)

**Chain:**

```
rt721 system_resume
  → "Initialization not complete, timed out"
  → PM -110
  → downstream slaves unattached / FW impossible
```

**Evidence (confirmed):**

- Every FAIL resume in manual traces (#24, #30, #40) shows rt721 timeout **before** `:8` PM -110.
- `:b` matrix 41/41 OK at kmsg level — asymmetry may be ordering, not separate `:b` bug.

**Falsify:** PASS run where rt721 also hits -110 but attach recovers (would downgrade H1).

**Next:** RT721 chronology at ms resolution (probe → resume → first xfer → timeout). **No kernel patch yet** — parse existing kmsg + optional dynamic_debug when sudo available.

---

## H2 — SDW master / bus state blocks re-attach

**Chain:**

```
PM resume failed on slave(s)
  → bus enumeration incomplete
  → sysfs status = Unattached (permanent until reboot?)
  → PCI rebind does not retry attach (boot #40)
```

**Evidence:**

- Boot #40: post-PCI probe but **only** `update_status_unattached` — no later attach in kmsg.
- Boot #30–38: post-PCI **attached** + `tas_io_init` — same -110 at wake, different recovery path.

**Questions:**

- Does SoundWire core retry attach after failed resume?
- Or: `resume FAIL → abandon`?

**Next:** Framework trace (`events/soundwire/` — **not present** on 7.0.0-27; see `phase6-trace-probe.sh`). Parse `soundwire/` dynamic_debug if enabled.

---

## H3 — Userspace race (PM vs PipeWire vs FW)

**Chain:**

```
PipeWire opens stream at T+3s
  → hw_params before attach/fw ready
  → playback without fw loop
  → px13 / PW stop makes state worse
```

**Evidence:**

- Boot #40: first `playback without fw` at T+14s while px13 still stopping PW.
- px13 false positive: declares done before WirePlumber opens stream (#24).

**Falsify:** PASS run with PW active before attach at same offset — would implicate ordering not race.

---

## H4 — ACP70 timing / load sensitivity

**Chain:**

```
Variable ACP/SMU resume latency
  → rt721 init window missed
  → FAIL branch
```

**Evidence (weak):**

- `-110` not 100% on every suspend in early matrix (some OK kmsg rows).
- IO_PAGE_FAULT on `snd_pci_ps` correlates with resume, not proven causal.

**Next:** Record `load1`, suspend type (s2idle), `offset_ms` variance across N PASS/FAIL pairs.

---

## Deprioritized (Phase 5, on hold)

| Old focus | Status |
|-----------|--------|
| TAS2783 FW stale `hw_init` (H-L1) | Partial fix (0003); **insufficient** when Unattached |
| TAS2783 asymmetric `:8` vs `:b` | Symptom of ordering / attach, not root |
| px13 recovery | Userspace mitigation; **mask --runtime bug** fixed in repo |

---

## Decision tree (after chronology diff)

```
First divergence at rt721 timeout?
  YES → instrument RT721 / ACPI SDCA path
  NO  → first divergence at attach?
          YES → SoundWire core / AMD manager
          NO  → first divergence at PW stream?
                  YES → userspace ordering / px13
                  NO  → TAS2783 FW path (0003 scope)
```
