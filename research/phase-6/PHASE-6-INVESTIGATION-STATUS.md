# Phase 6 investigation status (ACP70 / PX13)

English (canonical). Last updated: 2026-07-10 (runs 0005–0007).

**Progress estimate:** ~90% problem delimitation; **H1 (IRQ delivery)** strongly supported on run 0010 with full 0004 trace.

**First missing transition (run 0010):** `irq_enabled` → *(no `sdw0_irq` / `ping_irq` within 5s)* → `wait_init_timeout`.

See also: [SOUNDWIRE-RESUME-STATE-MACHINE.md](SOUNDWIRE-RESUME-STATE-MACHINE.md), [LINK-REENUMERATION-FAILURE.md](LINK-REENUMERATION-FAILURE.md)

---

## Project shift

| Phase | Goal | Status |
|-------|------|--------|
| 5 | Make laptop audio work (playback, FW, stereo) | Done |
| **6** | Why **intermittent** s2idle resume fails | **In progress** — SoundWire/ACP70 architecture |

RT721 and TAS2783 are **witnesses**, not root-cause candidates.

---

## Demonstrated causal chain

```text
system_resume
        │
        ▼
amd_resume_runtime()          ← runs (resume_enter pm=system_resume logged)
        │
        ▼
manager_reset                 ← runs (one amd call; bus dev=1,2,3 → UNATTACHED)
        │
        ▼
        ???                     ← THE GAP (no log evidence of PING/work/handle/ATTACHED)
        │
        ├── PASS (expected)
        │      ping_irq / ping_status
        │      queue_work
        │      handle_status
        │      bus UNATTACHED → ATTACHED
        │      completion
        │      RT721 OK
        │
        └── FAIL (observed)
               (silence in AMD+bus re-enumeration path)
               RT721 Type-1 and/or Type-2 (below)
               Dummy Output / no FW
```

**Conservative wording:** we observe **no log evidence** of post-reset re-enumeration activity in FAIL windows. That is compatible with “enumeration never starts” but must be confirmed with IRQ/`ping_irq` entry trace — not inferred from absence of `ping_status` alone.

---

## What bus instrumentation already answered

`soundwire-bus.ko` PHASE6 trace is **sufficient** for its question:

- Did `state_change → ATTACHED` occur post-reset?
- Did `completion` fire?

Answer in FAIL runs: **NO** for all slaves (dev 1, 2, 3).

**Do not add more bus.c trace** until AMD layer proves something reaches `sdw_handle_slave_status()`.

---

## Two FAIL classes (codec PM path)

| Class | Runs | Post-reset kernel trace | RT721 PM |
|-------|------|-------------------------|----------|
| **FAIL-1** | 0004, 0005, 0006 | `manager_reset` → all UNATTACHED → **no** AMD ping/work/handle logs | `wait_init_start` → **kernel t=+5210ms** timeout → `ret=-110` |
| **FAIL-2** | 0007 | `manager_reset` → **no** bus detach lines in narrow window; amd reset only | `resume_enter` → **`resume_early_exit reason=first_hw_init`** — **never** `wait_init_start` |

FAIL-2 means RT721 **does not enter** `wait_for_completion_timeout()` at all (`first_hw_init=0`, `unattach_req=0` at early resume). Still consistent with broken link — codec skips wait when not fully initialized.

Chronology run 0007: userspace `OK/WARN` with Dummy sink (audio broken); do not treat composite OK as PASS.

---

## Run reference table

| Run | Time | Resume path summary | Notes |
|-----|------|---------------------|-------|
| 0004 | 02:12:44 | reset → wait timeout -110 | First clean window capture |
| 0005 | 02:31:15 | reset → no ping/work → timeout -110 | FAIL-1; `resume=1` (pre resume_id patch) |
| 0006 | 02:55:08 | same as 0005 | FAIL-1, `run-6` |
| 0007 | 03:01:15 | reset → early_exit only | FAIL-2; `resume=2`; no wait_init |
| 0008 | 03:44:37 | reset → wait timeout -110 | FAIL-1; partial 0004 (no irq_enabled in ko) |
| 0009 | 03:50:54 | reset → wait timeout -110 | FAIL-1; partial 0004; IO_PAGE_FAULT YES |
| **0010** | 12:48:45 | **reset → irq_enabled → (silence) → timeout -110** | **FAIL-1; H1 signature; full 0004; IO_PAGE_FAULT NO |

Tools:

```bash
./scripts/phase6-experiment.sh sm RUN_ID   # includes Resume path block
./scripts/phase6-experiment.sh tl RUN_ID
```

---

## Revised hypotheses (post-reset chain)

| ID | ~% | Break | Log signature (when AMD trace complete) |
|----|---:|-------|----------------------------------------|
| **H1** | **70** | ACP SDW **IRQ never arrives** after enable | `irq_enabled resume=N` → **no** `sdw0_irq` / `ping_irq` *(run 0010)* |
| **H2** | 20 | IRQ but **empty status** / no work | `ping_irq` → no `queue_work` or bitmap=0 |
| **H3** | 8 | `queue_work` but empty `handle_status` / no ATTACHED | work logs, no bus ATTACHED |
| **H4** | 2 | SDW core skip | `handle_status` + ATTACHED in manager but bus skip — unlikely |

Previous codec/FW hypotheses: **deprioritized** (~5% combined).

---

## Binary question (answered on run 0010 — FAIL)

> After `amd_resume_runtime()` and `manager_reset`, does the ACP controller **receive and process the first event** (IRQ / ping) that should start SoundWire re-enumeration?

**Answer (run 0010, resume=1):** **NO.** `irq_enabled` logged at t=+~1ms post-reset; no `sdw0_irq`, `ping_irq`, or `queue_work` before RT721 `wait_init_timeout` at kernel t=+5358ms.

Narrow to: **ACP hardware IRQ delivery / interrupt routing** (pci-ps → manager irq_thread), not codec or bus core.

---

## Next instrumentation (H1 depth — proposed)

**Not** more bus.c. **Reduce** AMD trace to existence probes only:

| # | Location | Log |
|---|----------|-----|
| 1 | `amd_resume_runtime()` | `PHASE6 amd resume_enter resume=N` *(done)* |
| 2 | After `amd_enable_sdw_interrupts()` | `PHASE6 amd irq_enabled resume=N` *(done — run 0010)* |
| 3 | `pci-ps.c` `ACP_SDW0_STAT` → irq_thread **or** `amd_sdw_irq_thread` entry | `PHASE6 amd ping_irq resume=N` *(done — absent on resume=1)* |
| 4 | Before `schedule_work(amd_sdw_work)` | `PHASE6 amd queue_work resume=N` *(done — absent on resume=1)* |

**0004 complete.** Next probes (if H1 needs hardware proof):

| # | Location | Question |
|---|----------|----------|
| 5 | `pci-ps.c` `acp63_irq_handler` entry | Does **any** ACP IRQ fire post-resume? |
| 6 | `amd_enable_sdw_interrupts` | Log `ACP_EXTERNAL_INTR_CNTL` mask written |
| 7 | `readl(ACP_EXTERNAL_INTR_STAT)` poll after enable | Status bit ever set without handler? |

No masks, no slave states — only **did this step run** for `resume=N`.

Draft: [proposed/NEXT-AMD-IRQ-TRACE.md](proposed/NEXT-AMD-IRQ-TRACE.md)

Patch: [proposed/0004-phase6-amd-minimal-irq-trace.patch](proposed/0004-phase6-amd-minimal-irq-trace.patch) (applies on 0003; builds `soundwire-amd` + `snd-pci-ps`).

Legacy verbose trace: [proposed/0003-phase6-amd-sdw-trace.patch](proposed/0003-phase6-amd-sdw-trace.patch).

---

## IO_PAGE_FAULT correlation (open)

`snd_pci_ps` + `AMD-Vi: IO_PAGE_FAULT` appears at **resume timestamp** in FAIL runs 0004–0007 (same second as `suspend_exit` / `manager_reset` in chronology dumps). Not yet correlated with a true PASS run.

Track per run in Resume path block: `IO_PAGE_FAULT (window) YES/NO`.

| Run | IO_PAGE_FAULT at resume |
|-----|-------------------------|
| 0004–0007, 0009 | YES |
| **0010** | **NO** |
| PASS | *(none captured yet with AMD trace)* |

IO_PAGE_FAULT is **not required** for FAIL (0010 fails without it). Track but do not treat as sole cause.

---

## Upstream framing

> After system sleep resume on AMD ACP70, `manager_reset` clears all SoundWire slaves. In FAIL run 0010, `irq_enabled` completes but **no log evidence** of `ACP_SDW0_STAT` / `ping_irq` occurs within the RT721 wait window; slaves never return to ATTACHED. Transition **`irq_enabled` → (no IRQ delivery)`** is the first broken step. RT721 `-110` is downstream.

Still need ≥1 PASS with same trace for maintainer-ready contrast.

---

## Do not touch (yet)

- RT721 / TAS2783 behavior patches
- `soc_sdw_utils`, machine driver
- Additional `bus.c` instrumentation
- `sdw_handle_slave_status()` until something calls it post-reset

---

## Exit criteria (updated)

- [x] Bus model: post-reset no ATTACHED/completion (FAIL runs)
- [x] FAIL-1 vs FAIL-2 taxonomy
- [x] `sm` Resume path summary for quick run compare
- [x] Minimal AMD IRQ trace installed (`irq_enabled`, `ping_irq`, `queue_work`) — run 0010
- [x] ≥1 FAIL-1 with full chain bisect → **H1** (`irq_enabled` → silence)
- [ ] ≥1 true PASS with same trace + Resume path Case D
- [ ] IO_PAGE_FAULT correlation table (≥5 runs) — partial; not causal

---

## Commands

```bash
./scripts/build-phase6-sdw-trace.sh
./scripts/build-phase6-amd-trace.sh
./scripts/build-phase6-rt721-trace.sh
sudo reboot
sudo systemctl mask --runtime px13-audio-rebind.service

./scripts/phase6-experiment.sh disarm
./scripts/phase6-experiment.sh arm --notes run-N
systemctl suspend
# wait ~60s for worker

./scripts/phase6-experiment.sh sm
./scripts/phase6-experiment.sh tl
./scripts/phase6-experiment.sh status
```
