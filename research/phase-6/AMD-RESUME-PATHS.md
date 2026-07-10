# AMD SoundWire resume paths (ACP70 / PX13)

English (canonical). Static call-graph analysis — **no new instrumentation**.

See also: [SOUNDWIRE-BUS-CONTRACT.md](SOUNDWIRE-BUS-CONTRACT.md)

---

## Answer: can ATTACHED happen without `amd_sdw_update_slave_status_work()`?

**No.** On AMD, `grep sdw_handle_slave_status drivers/soundwire/amd_manager.c` shows a **single call site**:

```text
amd_sdw_update_slave_status_work()   [amd_manager.c:903]
    └── sdw_handle_slave_status()
```

There is no direct call from `amd_resume_runtime()`, ping helpers, or `pci-ps.c` to `sdw_handle_slave_status()`.

Therefore **`complete(initialization_complete)` always requires**:

```text
schedule_work(amd_sdw_work)
    → amd_sdw_update_slave_status_work()
        → sdw_handle_slave_status()
            → complete_all()
```

If FAIL shows no `completion`, the break is **before or inside** that chain — not in RT721/TAS2783.

---

## PM wiring (PX13)

```c
// amd_manager.c
SET_SYSTEM_SLEEP_PM_OPS(amd_suspend, amd_resume_runtime)
SET_RUNTIME_PM_OPS(amd_suspend_runtime, amd_resume_runtime, NULL)
```

**Both** system sleep and runtime PM use the same resume function: `amd_resume_runtime()`.

Distinction `system_resume` vs `runtime_resume` is **not visible** in `bus.c` today — would need a one-line PHASE6 trace in `amd_manager.c` later if required.

---

## Resume sequence (POWER_OFF mode — typical after full deinit)

```text
amd_resume_runtime()
    │
    ├─ clock / wake / ACP D0 (ACP70)
    │
    ├─ sdw_clear_slave_status(bus, SDW_UNATTACH_REQUEST_MASTER_RESET)   ← bus.c
    │       reason=manager_reset  (PHASE6 state_change → UNATTACHED)
    │       unattach_request = 1 on all slaves
    │
    ├─ amd_init_sdw_manager()
    ├─ amd_enable_sdw_interrupts()
    ├─ amd_enable_sdw_manager()
    └─ amd_sdw_set_frameshape()

(Parallel / later — device PM order dependent)
    Codec sdw_slave dev_resume (RT721 wait_init if unattach_request)
```

**CLK_STOP mode** resume (`amd_sdw_clock_stop_exit` only): **does not** call `sdw_clear_slave_status` in current code. If PX13 uses POWER_OFF (manager deinit on suspend), expect `manager_reset` on resume.

---

## Full IRQ → ATTACHED chain (static)

```text
snd_pci_ps IRQ handler                    sound/soc/amd/ps/pci-ps.c:210-224
    ACP_SDW0_STAT / ACP_SDW1_STAT
    schedule_work(&amd_manager->amd_sdw_irq_thread)

amd_sdw_irq_thread                        amd_manager.c:959
    read ACP_SW_STATE_CHANGE_STATUS_* 
    OR amd_sdw_read_and_process_ping_status()  → status[]
    schedule_work(&amd_manager->amd_sdw_work)

amd_sdw_update_slave_status_work          amd_manager.c:891
    sdw_handle_slave_status(bus, status[])
    [if status[0]==ATTACHED: ping loop → goto update_status]

sdw_handle_slave_status                   bus.c
    ATTACHED → sdw_initialize_slave → complete_all(init_complete)
```

### Four failure modes (maps to contract doc)

| # | Layer | What breaks |
|---|-------|-------------|
| 1 | `pci-ps.c` | No `ACP_SDWx_STAT` → irq_thread never scheduled |
| 2 | `amd_sdw_irq_thread` | status[] never ATTACHED for dev=3 (regs / ping) |
| 3 | `amd_sdw_irq_thread` | Early return (no status bits) → no `schedule_work(amd_sdw_work)` |
| 4 | `sdw_handle_slave_status` | `state_skip` — ATTACHED discarded |

Modes 1–3 → next trace in **AMD/ACP** (not bus.c). Mode 4 → **bus.c** skip logic.

---

## Who calls `sdw_clear_slave_status()` (UNATTACHED + unattach_request)

| Platform | When |
|----------|------|
| **AMD** `amd_manager.c:1381` | `amd_resume_runtime`, POWER_OFF branch, before manager re-init |
| Intel `intel_bus_common.c:101` | non-clock-stop0 resume |
| Intel aux | aux resume paths |

Only caller on PX13/ACP70: **AMD manager resume**.

---

## Files to read next (no instrumentation yet)

| File | Why |
|------|-----|
| `amd_manager.c` | PM ops, IRQ → work → handle_slave_status, ping loop |
| `amd_init.c` | Manager enable, clock, frame shape after resume |
| `amd_bus.c` (if present) / MCP command path | Ping response parsing |

There is no separate `amd_bus.c` in tree; MCP I/O is in `amd_manager.c` / `amd_init.c`.

---

## State machine comparison (PASS vs FAIL)

Use:

```bash
./scripts/phase6-state-machine.sh 0002 0003
journalctl -k -b 0 | ./scripts/phase6-state-machine.sh
```

**PASS (target):**

```text
sdw dev=3  ATTACHED → UNATTACHED  (manager_reset)
sdw dev=3  UNATTACHED → ATTACHED
sdw dev=3  completion  elapsed_ms=…
rt721      wait_init_ok | branch_fast_path
```

**FAIL A:**

```text
sdw dev=3  ATTACHED → UNATTACHED  (manager_reset)
rt721      wait_init_start
rt721      wait_init_timeout
(no sdw completion dev=3)
```

**FAIL B:**

```text
sdw dev=1  ATTACHED → UNATTACHED  (manager_reset)
sdw dev=1  SKIP (already_attached)
rt721      wait_init_timeout
```

---

## Probability note (Phase 6 working estimate)

| Layer | ~% |
|-------|---:|
| SoundWire core + AMD manager (ATTACHED never signaled) | 50 |
| ACP70 resume / power sequencing | 30 |
| RT721 (witness / wait) | 15 |
| TAS2783 | 5 |

---

## Related

- [SDW-INITIALIZATION-COMPLETE-MAP.md](SDW-INITIALIZATION-COMPLETE-MAP.md)
- [RT721-INSTRUMENTATION.md](RT721-INSTRUMENTATION.md)
