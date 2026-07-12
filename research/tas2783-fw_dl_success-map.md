# TAS2783 — `fw_dl_success` lifecycle map (kernel 7.0.0)

English (canonical). Static map for **Q2**: why `fw_dl_success` stays false after resume.

Source: `/usr/src/linux-source-7.0.0/sound/soc/codecs/tas2783-sdw.c`  
Runtime witness: [experiments/pcm-dual-path-trace-20260712.md](experiments/pcm-dual-path-trace-20260712.md)

---

## Where the flag lives

```c
struct tas2783_prv {
    ...
    bool fw_dl_task_done;
    bool fw_dl_success;
};
```

---

## The only assignment to `true`

**Function:** `tas2783_fw_ready()` — async callback from `request_firmware_nowait()`

```c
out:
    if (!ret)
        tas_dev->fw_dl_success = true;   /* ~798 */
    tas_dev->fw_dl_task_done = true;     /* always */
    wake_up(&tas_dev->fw_wait);
```

**Implication:** `fw_dl_success` becomes true **only** after:

1. Firmware file loaded from disk (`fmw` valid)
2. All `sdw_nwrite_no_pm()` segments to amp RAM succeed (`ret == 0`)

There is **no** other path that sets `fw_dl_success = true` (no resume shortcut, no PM callback).

---

## Where flags go `false`

| Site | When | Stock 7.0.0 |
|------|------|-------------|
| `tas_io_init()` start | Before SW reset + FW request | ✔ ~1145–1146 |
| `tas2783_fw_reinit()` | Patch 0003 only — before re-init | patch |
| `tas2783_sdca_dev_system_suspend()` | Patch 0003 only — invalidate on s2idle | patch |

**Stock system suspend** (`tas2783_sdca_dev_suspend`): only `regcache_cache_only(true)` — **does not** clear `fw_dl_success` or `hw_init`.

**Stock system resume** (`tas2783_sdca_dev_resume`): `regcache_sync` only — **does not** call `tas_io_init()` unless `unattach_request` + `initialization_complete` path.

---

## Who starts firmware download

**Only** `tas_io_init()`:

```text
tas_io_init()
  fw_dl_* = false
  SW reset
  request_firmware_nowait(..., tas2783_fw_ready)
  wait_event_timeout(fw_wait, fw_dl_task_done)   /* probe-time blocking wait */
  → init sequences if fw_dl_success
  → hw_init = true
```

**Callers of `tas_io_init()`:**

| Caller | Condition |
|--------|-----------|
| `tas_update_status()` | `status == ATTACHED && !hw_init` |
| `tas2783_fw_reinit()` | Patch 0003 — explicit re-init |
| `tas2783_sdca_dev_resume()` | Patch 0003 — `ATTACHED && !hw_init` |
| `tas_sdw_hw_params()` | Patch 0003 — stale FW + ATTACHED |

Stock after s2idle: slave often stays `ATTACHED` with `hw_init == true` → **`tas_io_init()` not called again** → amp RAM may be empty while flags say otherwise (stale success) **or** if flags cleared externally, no download restarts.

---

## `tas_sdw_hw_params()` failure path (observed 2026-07-12)

With patch **0007** (wait in hw_params) installed on test machine:

```text
tas_sdw_hw_params()
  if (!fw_dl_success && !fw_dl_task_done)
      wait_event_timeout(fw_wait, fw_dl_task_done, TIMEOUT)
      → timeout → "fw download wait timeout in hw_params"
  if (!fw_dl_success)
      → "error playback without fw download"
      → return -EINVAL
```

**Interpretation of `wait timeout` (not `firmware missing`):**

- `hw_params` blocked waiting for **`fw_dl_task_done`**
- `tas2783_fw_ready()` **never ran** or never completed the wait queue wake
- Therefore **`fw_dl_success` never got a chance to become true**

This is **completion/worker path** failure (user hypothesis C), not a format/capability rejection.

With patch **0003** additionally: hw_params may call `tas2783_fw_reinit()` first; if that fails or `request_firmware_nowait` fails synchronously without scheduling callback, same timeout.

---

## PM resume vs SoundWire `update_status`

| Path | Stock behavior after s2idle |
|------|----------------------------|
| `tas2783_sdca_dev_resume` | regcache sync; optional wait on `slave->initialization_complete` if `unattach_request` |
| `tas_update_status(ATTACHED)` | No-op if `hw_init` already true |
| Async FW | Not restarted |

SoundWire bus may re-enumerate (Phase 6–8) while codec driver **skips** `tas_io_init` because `hw_init` stayed true.

---

## Coherent Q2 model (inference — link to Phase 6–8 not proven in same run)

```text
resume
  → SoundWire re-enumeration incomplete / IRQ worker delayed (Phase 6–8)
  → tas_update_status(ATTACHED) skipped OR tas_io_init not reached
  → no request_firmware_nowait / tas2783_fw_ready
  → fw_dl_task_done stays false
  → hw_params wait timeout
  → fw_dl_success false
  → -EINVAL
```

**0006a** (manual `schedule_work` → enumeration OK) supports: if downstream init runs, FW path *can* complete.

---

## Fix target (already in repo)

| Patch | Addresses |
|-------|-----------|
| `upstream/series-B-firmware/0003` | Invalidate flags on system suspend; `tas2783_fw_reinit` on resume / hw_params |
| `0002` / `0007` | Wait in hw_params (symptom mitigation; exposes timeout clearly) |

Matrix claim: boots #30–#35 — 6/6 suspend OK with 0003 (see patch header).

---

## Grep (installed tree)

```bash
K=/usr/src/linux-source-7.0.0
rg -n 'fw_dl_success|fw_dl_task_done|tas2783_fw_ready|tas_io_init|tas2783_fw_reinit' \
  $K/sound/soc/codecs/tas2783-sdw.c
```

---

## Related

- [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md)
- [experiments/pcm-dual-path-trace-20260712.md](experiments/pcm-dual-path-trace-20260712.md)
- [../upstream/series-B-firmware/0003-ASoC-tas2783-reload-firmware-after-system-sleep.patch](../upstream/series-B-firmware/0003-ASoC-tas2783-reload-firmware-after-system-sleep.patch)
