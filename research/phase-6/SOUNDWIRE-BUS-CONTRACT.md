# SoundWire bus contract (Phase 6)

English (canonical). **Expected state machine** after system resume on PX13/ACP70.  
Each step is a **binary question** answerable from PHASE6 traces (RT721 + `soundwire-bus`).

Related: [SDW-INITIALIZATION-COMPLETE-MAP.md](SDW-INITIALIZATION-COMPLETE-MAP.md), [AMD-RESUME-PATHS.md](AMD-RESUME-PATHS.md)

---

## Expected contract (SYSTEM RESUME)

```text
PM: suspend exit
        │
        ▼
amd_resume_runtime()                    [AMD manager — not yet traced]
        │
        ├── clock / ACP D0 / manager re-init
        │
        ▼
sdw_clear_slave_status()                [bus.c — PHASE6: state_change → UNATTACHED, reason=manager_reset]
        │   reinit_completion() per slave
        │   unattach_request = 1
        │
        ▼
Codec dev_resume (RT721, TAS2783…)      [PHASE6 ctx=pm — RT721 module only]
        │   if unattach_request → wait_for_completion_timeout(5000ms)
        │
        │   ═══════════ parallel / ordering-dependent ═══════════
        │
        ▼
ACP PCI IRQ (snd_pci_ps)                [NOT traced — hypothesis layer]
        │
        ▼
schedule_work(amd_sdw_irq_thread)       [pci-ps.c]
        │
        ▼
Read status regs OR ping                [amd_sdw_irq_thread]
        │   → fills amd_manager->status[]
        │
        ▼
schedule_work(amd_sdw_work)               [amd_sdw_irq_thread]
        │
        ▼
amd_sdw_update_slave_status_work()      [NOT traced — sole entry to handle]
        │
        ▼
sdw_handle_slave_status()               [bus.c]
        │   UNATTACHED → ATTACHED transition
        │
        ▼
complete_all(initialization_complete)   [PHASE6: fn=completion elapsed_ms=…]
        │
        ▼
RT721 wait returns OK                   [PHASE6: wait_init_ok | branch_fast_path]
        │
        ▼
TAS2783 attach / FW / PCM               [PHASE5 — observer only]
        │
        ▼
Audio
```

---

## PX13 device numbering (link 1)

| dev | uid | Device |
|-----|-----|--------|
| 1 | 0xb | TAS2783 |
| 2 | 0x8 | TAS2783 |
| 3 | 0xff | **RT721** |

## Binary checklist (one resume cycle, dev=3 RT721)

| # | Step | Question | PASS evidence | FAIL evidence |
|---|------|----------|---------------|---------------|
| 1 | UNATTACHED | Does `state_change new=UNATTACHED` occur? | ✅ expected | ✅ observed |
| 2 | `reason=manager_reset` | From `sdw_clear_slave_status` on AMD resume? | ✅ | ✅ (to confirm) |
| 3 | RT721 wait | Does `wait_init_start` run? | if unattach_req=1 | ✅ |
| 4 | IRQ → work | *(not visible yet)* Did ACP SDW IRQ fire before timeout? | TBD | TBD |
| 5 | `status[]` ATTACHED | Does `state_change new=ATTACHED` for dev=3? | ✅ | ❌ **key** |
| 6 | `completion` | Does `fn=completion dev=3` appear? | ✅ | ❌ |
| 7 | `elapsed_ms` | Time from UNATTACHED to completion? | ~ms | N/A or >5000 |
| 8 | RT721 exit | `wait_init_ok` or `branch_fast_path`? | ✅ | `wait_init_timeout` |
| 9 | `state_skip` | Case B: `already_attached` without completion? | ❌ | ? |

**Session goal:** prove row 5 — ATTACHED **never from hardware path** vs **lost in framework** (row 9).

---

## IRQ path — four failure modes (before `sdw_handle_slave_status`)

Static AMD chain (see [AMD-RESUME-PATHS.md](AMD-RESUME-PATHS.md)):

```text
IRQ (pci-ps.c)
    → amd_sdw_irq_thread
        → read status_change_* OR ping → status[]
        → schedule_work(amd_sdw_work)
            → sdw_handle_slave_status()   ← ONLY caller on AMD
```

| Mode | Symptom in current traces | Next instrumentation (if needed) |
|------|---------------------------|----------------------------------|
| **1** No IRQ | No ATTACHED, no completion; no bus activity in 5s | 1 line in `pci-ps.c` or `amd_sdw_irq_thread` entry |
| **2** IRQ but `status[]` never ATTACHED for dev=3 | No `state_change new=ATTACHED` | Trace `status[3]` after register read / ping |
| **3** ATTACHED in `status[]` but no work | Would need irq_thread without `schedule_work` | Trace `schedule_work(amd_sdw_work)` |
| **4** Work runs, handle discards | `state_skip reason=already_attached` or `from_alert` | Already in bus PHASE6 |

**Static answer:** On AMD, **no** path to `complete(initialization_complete)` without `amd_sdw_update_slave_status_work()` → `sdw_handle_slave_status()`. Boot/resume ATTACHED must traverse IRQ → irq_thread → (optional ping) → amd_sdw_work.

---

## Timing template (fill from journal, `-o short-precise`)

Anchor: RT721 `resume_enter t=+0` or first `state_change UNATTACHED`.

| Event | PASS (example) | FAIL (known) |
|-------|----------------|--------------|
| `resume_enter` | +0 ms | +0 ms |
| `state_change → UNATTACHED` | +0–1 ms | +0 ms (`manager_reset`) |
| `wait_init_start` | +0 ms | +0 ms |
| IRQ / irq_thread | **?** | **?** |
| `state_change → ATTACHED` | **?** | **missing** |
| `completion dev=3` | **?** | **missing** |
| `wait_init_ok` / `branch_fast_path` | ~5 ms | — |
| `wait_init_timeout` | — | ~5441 ms |
| `resume_exit ret=` | 0 | -110 |

If IRQ appears at +4000 ms on FAIL, hypothesis shifts to **late re-enumeration** (timeout too short), not absent ATTACHED.

Extract (resume window only — not full boot):

```bash
./scripts/phase6-experiment.sh sm --last-resume
./scripts/phase6-experiment.sh matrix --last-resume
./scripts/phase6-experiment.sh matrix RUN_PASS RUN_FAIL
./scripts/phase6-experiment.sh window RUN_ID   # save/show kmsg-phase6-window.log
```

Window: `suspend_entry - 5s` … `suspend_exit + 15s`. Matrix rows marked **(post)** filter events after `manager_reset`.

---

## Transition matrix (PASS vs FAIL)

Tool: [`scripts/phase6-transition-matrix.sh`](../../scripts/phase6-transition-matrix.sh)

| Transition | PASS | FAIL |
|------------|------|------|
| ATTACHED → UNATTACHED | ✅ | ✅ |
| UNATTACHED → ATTACHED (dev=3) | ✅ | ❌ |
| ATTACHED → ALERT | — | — |
| `completion` (dev=3) | ✅ | ❌ |
| `state_skip` (dev=3) | ❌ | ? |
| `wait_init_ok` / fast path | ✅ | ❌ |
| `wait_init_timeout` | ❌ | ✅ |

Template CSV: [`templates/phase6-transition-matrix.csv`](templates/phase6-transition-matrix.csv)

---

## Observers only (no further codec instrumentation)

| Component | Role |
|-----------|------|
| RT721 PHASE6 | Wait timeline, `unattach_req`, timeout |
| soundwire-bus PHASE6 | State machine + completion |
| TAS2783 PHASE5 | Downstream cascade only |

---

## Next session — single objective

> **Prove whether ATTACHED never arrives from hardware (modes 1–2) or arrives and is dropped (modes 3–4).**

If consistent FAIL A (no `state_change new=ATTACHED`, no `state_skip`): next patch target **`drivers/soundwire/amd/` + `sound/soc/amd/ps/pci-ps.c`** (IRQ / status read), not `bus.c` logic.

If FAIL B (`state_skip`): next target **`bus.c`** `sdw_handle_slave_status` skip paths.

---

## alsa-devel one-liner (when matrix is filled)

> After s2idle, AMD `sdw_clear_slave_status()` forces UNATTACHED and codecs wait on `initialization_complete`. On FAIL, RT721 times out at 5s because `sdw_handle_slave_status()` never completes initialization for dev=3 — either no ATTACHED in manager status[] or handle skips the transition. TAS2783 failure is downstream.
