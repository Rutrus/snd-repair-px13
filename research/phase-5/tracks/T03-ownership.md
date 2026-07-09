# T03 — Structure ownership after suspend

## Chain

```
sdw_slave
  → sdw_slave.driver_data
  → tas2783_prv (tas_dev)
      → fw_dl_success
      → fw_dl_task_done
      → fw_wait
      → sdw_peripheral
  → sdw_stream_runtime (per stream)
      → slave_rt[]
      → port_runtime[]
```

## Questions (post-resume)

| Struct | Re-init? | Reused stale? | Owner frees? |
|--------|----------|---------------|--------------|
| `tas_dev` | | | |
| `fw_dl_success` | | | |
| `sdw_stream_runtime` | | | |
| `slave_rt` | | | |

## Method

1. Grep `devm_kzalloc` / `kfree` / `reset` in tas2783 + sdw core.
2. On resume FAIL boot, compare `dev_info` uid vs probe order — re-probe or same device?
3. If same `sdw_slave` without `remove()` → flags may be stale.

## Code anchors (kernel tree)

- `linux-source-*/sound/soc/codecs/tas2783-sdw.c` — `tas2783_prv`, fw async work
- `sound/soc/soundwire/slave.c` — attach lifecycle
