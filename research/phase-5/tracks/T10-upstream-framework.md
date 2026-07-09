# T10 — Upstream / maintainer framing

## One-sentence hypothesis (validated)

> **TAS2783 firmware lives in amplifier RAM; the driver must treat system sleep as invalidating `hw_init` and async FW state, and re-run `tas_io_init()` on resume — not assume one-shot boot initialization persists.**

## Property violated (phase 5 outcome)

| Property P | Violated if | Evidence |
|------------|-------------|----------|
| FW reload on warm resume | `hw_init==true` blocks `tas_io_init` after sleep | T02 PHASE5 + #24 vs #30–35 |
| Async FW complete before PCM open | hw_params waits forever when no task started | #24 timeline |
| Per-slave independence | `:b` OK while `:8` broken | pre-0003 matrix (asymmetric WARN) |

## Upstream series

[`../../upstream/series-B-firmware/`](../../upstream/series-B-firmware/)

| Patch | Purpose |
|-------|---------|
| 0001 | Retry `-ETIMEDOUT` on FW write |
| 0002 | Wait in hw_params for async FW |
| **0003** | **Reload FW after system sleep** |

## Cover letter paragraph (draft)

```
Patch 3/3 addresses suspend/resume on dual-TAS2783 SoundWire links (tested
on ASUS ProArt PX13, AMD ACP70). Firmware is downloaded into amp RAM once at
attach; after s2idle the driver kept hw_init while no download task was
running, so hw_params blocked on fw_dl_task_done. Invalidate FW bookkeeping
on system_suspend and re-trigger tas_io_init from resume paths. Six
consecutive suspend/resume cycles show both slaves reaching FW OK; PM -110
from ACPI may still occur and is handled separately by platform recovery.
```

## Reference

- Phase 5 lab patches: [`../proposed/`](../proposed/)
- Validation: `validation/fw-matrix.csv` rows 30–35
