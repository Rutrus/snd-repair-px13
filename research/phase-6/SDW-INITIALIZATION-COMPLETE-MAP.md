# SoundWire `initialization_complete` — static map (Phase 6)

English (canonical). **Project focus:** ACP70 link re-enumeration after `manager_reset`, not codec drivers.

RT721 **waits**; the bus **signals** via `complete_all()`. AMD manager **feeds** `status[]` from PING/IRQ.

**Patches:** bus [`0002`](proposed/0002-phase6-sdw-bus-trace.patch), AMD [`0003`](proposed/0003-phase6-amd-sdw-trace.patch)  
**Timeline:** [`scripts/phase6-resume-timeline.sh`](../../scripts/phase6-resume-timeline.sh)

---

## PX13 device numbering (link 1)

| dev | uid | Device |
|-----|-----|--------|
| 1 | 0xb | TAS2783 |
| 2 | 0x8 | TAS2783 |
| 3 | 0xff | **RT721** (first waiter on timeout) |

---

## Full re-enumeration path (post system resume)

```text
amd_resume_runtime()  [pm=system_resume, POWER_OFF]
    │
    ├─ PHASE6 amd fn=manager_reset t=+0ms
    ├─ sdw_clear_slave_status()  → bus state_change UNATTACHED (all dev)
    │
    ├─ (hardware enumerates)
    │
    ├─ IRQ → amd_sdw_irq_thread
    │       ├─ amd_sdw_read_and_process_ping_status()
    │       │     PHASE6 amd fn=ping_status t=+Nms resp=0x…
    │       └─ schedule_work → PHASE6 amd fn=queue_work t=+Nms devmask=…
    │
    ├─ amd_sdw_update_slave_status_work()
    │       PHASE6 amd fn=handle_status t=+Nms st0..st3=…
    │       └─ sdw_handle_slave_status()
    │             bus state_change UNATTACHED→ATTACHED
    │             bus fn=completion elapsed_ms=N phase=resume
    │             complete_all(initialization_complete)
    │
    └─ Codec PM: RT721 wait_init_ok / branch_fast_path
```

**FAIL (run 0004):** chain breaks after `manager_reset` — no post-reset `ATTACHED` / `completion` for **any** dev.

---

## Bus autómata (minimal instrumentation)

```text
PASS:  ATTACHED → UNATTACHED (manager_reset) → ATTACHED → completion
FAIL:  ATTACHED → UNATTACHED (manager_reset) → … → wait_init_timeout
```

| Event | Meaning |
|-------|---------|
| `state_change` + `reason=` | Transition + detach cause |
| `completion` + `elapsed_ms` + `phase=` | `complete_all()` fired |
| `state_skip` | Case B — ATTACHED discarded |

---

## Who signals `complete_all`?

| Location | Condition |
|----------|-----------|
| `bus.c:sdw_handle_slave_status()` | UNATTACHED→ATTACHED, not `from_alert` / `already_attached` skip |

**Never signals if:** `state_skip reason=already_attached|from_alert`, or ATTACHED never reaches handle.

---

## Experiment matrix (RT721 = dev=3)

| Outcome | Bus (post-reset) | RT721 PM |
|---------|------------------|----------|
| **PASS** | `UNATTACHED→ATTACHED` + `completion dev=3` | `wait_init_ok` / fast path |
| **FAIL global** | reset, no re-attach **any dev** | `wait_init_timeout` |
| **FAIL B** | `state_skip` without completion | timeout |

Global stall (all dev) → AMD manager path, not single codec.

---

## Do not instrument further (by design)

- RT721 / TAS2783 (witness only)
- `soc_sdw_utils`, machine driver

Until AMD `ping_status` / `handle_status` bisects A/B/C.

---

## Related

- [LINK-REENUMERATION-FAILURE.md](LINK-REENUMERATION-FAILURE.md)
- [AMD-RESUME-PATHS.md](AMD-RESUME-PATHS.md)
- [SOUNDWIRE-BUS-CONTRACT.md](SOUNDWIRE-BUS-CONTRACT.md)
