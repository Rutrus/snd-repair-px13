# T02 — PM callback instrumentation

## Goal

Trace **lifecycle**, not isolated `hw_params`.

## Callback list

| File | Functions |
|------|-----------|
| `tas2783-sdw.c` | `probe`, `remove`, `runtime_suspend`, `runtime_resume`, `suspend`, `resume`, `tas2783_fw_ready` |
| `rt721-sdca*.c` | same PM surface (reference) |
| `soundwire/master.c` | master PM, stream enable |
| `soundwire/bus.c` | attach, detach, enumeration |
| `soundwire-amd` / `amd_manager.c` | manager resume |

## Key question

```
resume → fw_ready() → runs again?
         yes → why done=0?
         no  → lifecycle gap (not FW timeout)
```

## Patch policy (this branch)

- **Allowed:** `PHASE5` trace lines only (like ENZOPLAY but PM-focused)
- **Forbidden:** new retries, sleeps, or behavior changes until T01/T05 complete

Proposed patch series: `research/phase-5/proposed/0001-phase5-pm-trace.patch` (draft, not applied)

## Evidence so far (resume 22:40)

- PM `-110` on `:8`, `:b`, rt721 at `suspend exit`
- px13 PCI reset → card present → **no** `:8` FW errors for 30s
- WirePlumber → `:8 done=0` at +48s — suggests **fw_ready path not re-established**, not slow FW
