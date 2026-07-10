# Phase 6 investigation status (ACP70 / PX13)

English (canonical). Last updated: 2026-07-10 (runs 0010–0011).

**Progress estimate:** ~92% delimitation. **Inflection point (commit 507e789 / run 0010):** investigation is no longer about codecs or SoundWire core — it is why the **ACP70 IRQ chain stops after a correct `manager_reset` + interrupt enable**.

**Filled link (run 0010):** `manager_reset` → **`irq_enabled`** → *(no SDW IRQ in log)* → `wait_init_timeout` (-110).

See also: [SOUNDWIRE-RESUME-STATE-MACHINE.md](SOUNDWIRE-RESUME-STATE-MACHINE.md), [proposed/NEXT-ACP-HW-IRQ-TRACE.md](proposed/NEXT-ACP-HW-IRQ-TRACE.md)

---

## What is now solid

### 1. `amd_enable_sdw_interrupts()` is not the problem

Run 0010 logs `irq_enabled` immediately after `manager_reset`. Hypothesis *"AMD never re-enables interrupts"* is **ruled out**.

### 2. Break is after enable — do not instrument earlier layers

```text
resume
│
├── enable IRQ          ✅ (irq_enabled)
│
├── hardware IRQ?       ← ACTIVE SEARCH
├── IRQ routing?
├── handler runs?
├── irq_thread runs?
├── ping_status?
└── queue_work?
```

No further trace in PM resume entry, `manager_reset` setup, or bus.c until IRQ chain is bisected.

### 3. Codecs are witnesses only

RT721 `-110` and TAS2783 no-FW are **downstream** of missing `initialization_complete()`.

---

## Demonstrated causal chain (updated)

```text
system_resume
        │
        ▼
amd_resume_runtime()          ✅ resume_enter
        │
        ▼
manager_reset                 ✅ t=+0ms
        │
        ▼
irq_enabled                   ✅ run 0010/0011 (amd_enable_sdw_interrupts)
        │
        ▼
        ???                     ← GAP: no sdw0_irq / ping_irq / queue_work (resume=N)
        │
        ├── PASS (needed)
        │      sdw0_irq → ping_irq → queue_work → ATTACHED → completion
        │
        └── FAIL (0010)
               wait_init_timeout @ kernel t=+5358ms → -110
```

---

## Hypotheses (revised post-0010)

| ID | ~% | Statement |
|----|---:|-----------|
| **H-IRQ** | **80** | **ACP→SDW interrupt chain** (hardware assert, firmware, or PCI/routing) — STAT never fires or handler never sees it |
| **H-SDW** | 15 | IRQ arrives but SDW protocol path empty (S4: `ping_irq` with sc=0) |
| **H-other** | 5 | Unlikely: SDW core skip, codec, FW |

Former H2–H4 collapse into H-SDW once hardware IRQ is proven.

### Ruled out or deprioritized

| Item | Status |
|------|--------|
| AMD never enables IRQs | **Ruled out** (0010) |
| Codec root cause | **Witness** |
| SoundWire bus core (pre-IRQ) | **Deprioritized** |
| IO_PAGE_FAULT as necessary cause | **Demoted** — see observations |

---

## Four scenarios (next bisect — 0005)

| # | Observation | Points to |
|---|-------------|-----------|
| **S1** | `ACP_EXTERNAL_INTR_STAT` SDW bit never set | HW / FW / ACP block |
| **S2** | STAT bit set, no `acp_irq_handler` / `sdw0_irq` | IRQ routing, mask, IOMMU |
| **S3** | handler runs, no `ping_irq` | workqueue / `schedule_work` |
| **S4** | `ping_irq`, empty status, no `queue_work` | SDW protocol |

Draft: [proposed/NEXT-ACP-HW-IRQ-TRACE.md](proposed/NEXT-ACP-HW-IRQ-TRACE.md)

---

## FAIL classes (codec witness path)

| Class | Runs | RT721 |
|-------|------|-------|
| **FAIL-1** | 0004–0006, 0008–0010 | `wait_init` → timeout `-110` |
| **FAIL-2** | 0007, **0011** | `resume_early_exit` (`first_hw_init`); no wait |

Run **0011** (`resume=2`, same boot after 0010): same `irq_enabled` → silence, but FAIL-2 because `hw_init=0` from prior FAIL. Chronology `OK/WARN` + Dummy is **not** PASS. Use **clean reboot** before PASS capture.

---

## Run reference table

| Run | Time | AMD post-reset | Notes |
|-----|------|----------------|-------|
| 0010 | 12:48:45 | reset → **irq_enabled** → silence → -110 | **FAIL-1; inflection run**; IO_PAGE_FAULT **NO** |
| 0011 | 12:53:42 | reset → irq_enabled → silence | FAIL-2 cascade; `resume=2`; IO_PAGE_FAULT YES |

Earlier: 0004–0009 in git history; pre-`irq_enabled` runs useful but superseded by 0010.

```bash
./scripts/phase6-experiment.sh sm 0010
./scripts/phase6-experiment.sh tl 0010
```

---

## Observations (not primary hypotheses)

### IO_PAGE_FAULT

`snd_pci_ps` + `AMD-Vi: IO_PAGE_FAULT` appears in some FAIL windows (0004–0009, 0011) but **run 0010 FAILs without it**.

| Run | IO_PAGE_FAULT |
|-----|---------------|
| 0004–0009, 0011 | YES |
| **0010** | **NO** |

**Conclusion:** temporal **correlation** only — not a necessary cause. Keep in Resume path block; do not drive patch target.

---

## Upstream framing (maintainer-ready when PASS captured)

**FAIL (0010):**

> After s2idle resume on ACP70, `manager_reset` and `amd_enable_sdw_interrupts()` complete (`irq_enabled`). No log evidence of `ACP_SDW0_STAT` / manager IRQ processing occurs before RT721 times out waiting for `initialization_complete()`. First broken transition: **`irq_enabled` → (no IRQ delivery)`**.

**Contrast needed:**

```text
PASS:  manager_reset → irq_enabled → sdw0_irq → ping_irq → queue_work → ATTACHED → completion
FAIL:  manager_reset → irq_enabled → (nothing) → timeout
```

---

## Instrumentation status

| Patch | Probes | Status |
|-------|--------|--------|
| 0003 | verbose amd + resume=N | Installed |
| 0004 | irq_enabled, sdw0_irq, ping_irq, queue_work | Installed (0010) |
| **0005** | intr_stat_post_enable, acp_irq_handler_enter | **Proposed** |

---

## Exit criteria

- [x] `irq_enabled` proves enable path runs
- [x] First missing step identified on FAIL-1 (0010)
- [x] IO_PAGE_FAULT demoted to observation
- [ ] 0005 hardware/routing bisect (S1–S4)
- [ ] ≥1 **clean-boot PASS** with same trace (Case D)
- [ ] PASS vs FAIL first-divergence table for upstream

---

## Commands

```bash
./scripts/build-phase6-amd-trace.sh   # 0003+0004 today; 0005 when landed
sudo reboot                           # required before PASS attempt

sudo systemctl mask --runtime px13-audio-rebind.service
./scripts/phase6-experiment.sh disarm
./scripts/phase6-experiment.sh arm --notes run-N-clean-boot
systemctl suspend

./scripts/phase6-experiment.sh sm RUN_ID
```
