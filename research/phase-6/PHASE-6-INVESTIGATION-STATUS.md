# Phase 6 investigation status (ACP70 / PX13)

English (canonical). Last updated: 2026-07-10 (runs 0010–0012).

**Progress:** ~92% delimitation. **Method:** uncertainty shrinks one layer per iteration — not shotgun patching.

**Canonical facts (do not re-debate):** [KNOWN-FACTS.md](KNOWN-FACTS.md)

---

## Problem statement (demonstrated)

> The first observable failure occurs **after** `amd_resume_runtime()` executes `manager_reset` and re-enables interrupts. All SoundWire re-enumeration activity then **disappears from the log** until RT721 exhausts `wait_for_completion_timeout()` (~5 s, `-110`).

Supported by repeated FAIL-1 runs (0010, 0012): `manager_reset` + `irq_enabled` always; no `sdw0_irq` / `ping_irq` / `queue_work` / `ATTACHED` / `completion`.

---

## Upstream diagram (maintainer entry point)

```text
resume
   ↓
manager_reset                    ✅ always (FAIL-1)
   ↓
irq_enabled                      ✅ always (0010, 0012)
   ↓
────────────────────────────────  ← first reproducible gap
(no ACP interrupt activity in log)
────────────────────────────────
   ↓
no UNATTACHED → ATTACHED
   ↓
no completion()
   ↓
RT721 wait_init_timeout (-110)   witness only
```

A maintainer can start work **at the gap** — not at RT721 or TAS2783.

---

## What is proven vs what is not

| Statement | Status |
|-----------|--------|
| `manager_reset` runs | **Proven** |
| `irq_enabled` runs | **Proven** (0010, 0012) |
| No downstream SDW activity in log | **Proven** (FAIL-1) |
| RT721 `-110` is consequence | **Proven** |
| Hardware never asserts IRQ | **Not proven** — only *no IRQ observable by current trace* |
| IRQ routing broken | **Not proven** — 0005 bisects S1 vs S2 |

Remaining branches after enable (0005 target):

```text
enable IRQ
      │
      ├── HW never raises STAT bit          → S1
      ├── HW raises bit, lost before handler → S2
      ├── handler enters, exits early
      └── handler takes non-SDW path
```

---

## Hypotheses (post-0010 / 0012)

| ID | ~% | Scope |
|----|---:|-------|
| **H-ACP** | **80** | ACP IRQ chain: hardware assert or PCI/routing (S1/S2) |
| **H-SDW** | 15 | After IRQ proven: protocol / empty status |
| **H-other** | 5 | Codec, FW, bus core skip |

See [KNOWN-FACTS.md](KNOWN-FACTS.md) for ruled-out items.

---

## FAIL classes

| Class | RT721 | Runs |
|-------|-------|------|
| **FAIL-1** | `wait_init` → `-110` | 0004–0006, 0008–0010, **0012** |
| **FAIL-2** | `resume_early_exit` | 0007, 0011 (cascade; `resume≥2`) |

Chronology `OK` + Dummy ≠ PASS. Clean reboot before PASS capture.

---

## Run reference (recent)

| Run | Post-reset AMD | Notes |
|-----|----------------|-------|
| 0010 | reset → irq_enabled → silence → -110 | Inflection; IO_PAGE_FAULT NO |
| 0012 | same as 0010 | **Reproduces** 0010; IO_PAGE_FAULT NO |
| 0011 | irq_enabled → silence | FAIL-2 cascade |

```bash
./scripts/phase6-experiment.sh sm 0012
```

---

## Instrumentation

| Patch | Purpose | Status |
|-------|---------|--------|
| 0003 | resume=N, bus witness | Installed |
| 0004 | irq_enabled, sdw0_irq, ping_irq | Installed |
| **0005** | **S1/S2 only:** `intr_stat_post_enable`, `irq_handler_enter`, `irq_thread_enter` | Ready — [0005](proposed/0005-phase6-s1-s2-bisect.patch) |

0005 instruments **ACP only** — not more SoundWire / `ping_status`.

---

## Frozen scope

RT721, TAS2783, machine driver, 0003 FW reload, PipeWire, `px13-audio-rebind`, extra `bus.c` — sufficient separation achieved.

---

## PASS value (when it appears)

Same instrumentation; first divergence is the entire upstream story:

```text
FAIL:  reset → irq_enabled → (silence) → timeout
PASS:  reset → irq_enabled → handler → ping → queue_work → ATTACHED → completion
```

Not required to continue S1/S2 bisect, but **gold** for maintainer report.

---

## Exit criteria

- [x] Known facts documented ([KNOWN-FACTS.md](KNOWN-FACTS.md))
- [x] Reproducible FAIL-1 gap (0010 + 0012)
- [x] `irq_enabled` proven; IO_PAGE_FAULT demoted
- [ ] 0005 run: S1 or S2 on clean-boot FAIL
- [ ] Optional: clean-boot PASS with same trace

---

## Commands

```bash
./scripts/build-phase6-amd-trace.sh   # 0003+0004+0005
sudo reboot
./scripts/phase6-experiment.sh arm --notes run-13-s1s2
systemctl suspend
./scripts/phase6-experiment.sh sm
```
