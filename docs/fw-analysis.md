# Firmware matrix analysis — 2026-07-09

> **English** | [Español](es/analisis-fw.md)

## Unique boots (6 real reboots)

| Boot | boot_id (8 chars) | :8 Left | :b Right | Audio |
|------|-------------------|---------|----------|-------|
| 1 | 8ecd0bbc | WARN | **FAIL(fw)** | left only |
| 2 | 8bc7932c | WARN | OK | left only |
| 3 | 28347f62 | WARN | OK | left only |
| 4 | 79e6d74b | WARN | **FAIL(fw)** | left only |
| 5 | 8e8f7349 | WARN | **FAIL(fw)** | left only |
| 6 | 8681aafb | WARN | OK | left only |

## Demonstrated by the matrix

1. **`:8` never logs `FW download failed`** on any boot.
2. **`:b` fails FW intermittently** — 3/6 boots with `-110` (~50%).
3. **`:8` always `WARN(no-fw-hw_params)`** — PipeWire calls `hw_params` before async download finishes.
4. **Audio always left-only** even when `:b` = OK → right channel does not depend only on probe FW success; early `hw_params` or stream link to `tas2783-2` also fails.

## Compatible with (not yet proven)

- Temporary contention in `sdw_nwrite_no_pm` when downloading FW in parallel (only `:b` loses, does not alternate `:8`/`:b`).
- PipeWire race vs `request_firmware_nowait` on `:8` (WARN without nwrite FAIL).

## Not compatible with

- Deterministic failure always on the same UID in nwrite (`:8` never fails).
- Deep `soundwire-amd` or SDW transport bug.

## Applied patches (0006 + 0007)

| Patch | Effect |
|-------|--------|
| **0006** | Retry ×5, 10 ms, on `-ETIMEDOUT`/`-EAGAIN` during FW download |
| **0007** | `hw_params` waits for `fw_dl_task_done` before rejecting playback |

## Post-reboot verification

```bash
./scripts/collect-tas2783-fw.sh >> ~/tas2783-fw-matrix.log
speaker-test -D plughw:1,2 -c 2 -t wav -l 1
echo "  AUDIO: left-only | L+R" >> ~/tas2783-fw-matrix.log
```

## Boot 7 — first boot with FW OK on both

| `:8` | `:b` | Audio |
|------|------|-------|
| OK | OK | left only (still) |

**Conclusion:** 0006+0007 address FW download; the remaining blocker was ASoC routing (Problem C). See [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md).
