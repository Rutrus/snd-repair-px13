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

| Patch | Path |
|-------|------|
| 0001 PM trace (lab) | [`../proposed/0001-phase5-pm-trace.patch`](../proposed/0001-phase5-pm-trace.patch) |
| 0002 FW reload (lab) | [`../proposed/0002-phase5-fw-reload-on-resume.patch`](../proposed/0002-phase5-fw-reload-on-resume.patch) |
| 0003 FW reload (upstream) | [`../../upstream/series-B-firmware/0003-ASoC-tas2783-reload-firmware-after-system-sleep.patch`](../../upstream/series-B-firmware/0003-ASoC-tas2783-reload-firmware-after-system-sleep.patch) |

Build lab: `./scripts/build-phase5-proposed.sh` · upstream: `./scripts/build-from-upstream.sh`

## Evidence

### Resume #24 (pre-0003) — FAIL

- PM `-110` on `:8`, `:b`, rt721 at `suspend exit`
- px13 PCI reset → card present → **no** `probe`/`fw_ready` in kmsg 22:41:05–37
- WirePlumber → `:8 done=0` at +48s
- **H-L1 confirmed:** `tas_io_init()` blocked by stale `hw_init`

### Resume #30–#35 (post-0003) — OK (6/6)

- PM `-110` still at wake (unchanged)
- `system_suspend` clears `hw_init` / `fw_dl_*` (PHASE5 trace)
- px13 PCI reset → `remove` + `probe` + `tas_io_init` + `fw_ready_done`
- Matrix: `:8=OK :b=OK`, 0× `playback without fw`
- Invariants I1–I2 hold; no Dummy Output

**Conclusion:** lifecycle gap fixed by invalidating FW state on system sleep and re-running `tas_io_init()`. Not a bus-timeout retry issue.
