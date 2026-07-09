# Priority — full resume trace (ACP → first trigger)

> **Phase 5 spine.** All other tracks feed evidence into this document.

---

## Question

From **ACP leaving system suspend** until **first PCM `trigger()` reaches UID `:8`**, which callback chain runs — and where does `fw_dl_success` / `fw_dl_task_done` stop being true?

---

## Hypothesis under test

| ID | Hypothesis | If true |
|----|------------|---------|
| H-L1 | `tas2783_fw_ready()` **never re-runs** on resume | Lifecycle bug, not FW timeout |
| H-L2 | FW starts **before bus is operational** | Ordering bug → `-110` |
| H-L3 | `tas_priv` / `fw_dl_*` **reused stale** after PM | Ownership bug (T03) |
| H-L4 | Only `:8` slave PM path differs from `:b` | ACPI/DisCo asymmetry |

---

## Required instrumentation (T02 — design only until approved)

Trace with **boot/resume tag** in:

```
sound/soc/codecs/tas2783-sdw.c   probe, remove, runtime_suspend/resume, system suspend/resume
sound/soc/codecs/rt721-sdca*.c   same (reference path)
sound/soc/soundwire/*.c          master resume, slave attach/detach
sound/soc/amd/*.c                amd_manager resume, ps-sdw-dma
```

Each line: `PHASE5[ctx=boot|resume] fn=... uid=0x%x fw_done=%d fw_ok=%d t=+%lldms`

Use `ktime_get_boottime_ns()` delta from first `PM: suspend exit` in same boot.

**No new retry logic** — observation only.

---

## Timeline template (fill per resume)

| +ms | Layer | Event | :8 fw_done | :8 fw_ok | :b fw_done | :b fw_ok |
|-----|-------|-------|------------|----------|------------|----------|
| 0 | PM | `suspend exit` | | | | |
| | ACP | manager resume | | | | |
| | SDW | bus / master up | | | | |
| | SDW | slave :8 attach | | | | |
| | SDW | slave :b attach | | | | |
| | TAS | probe or re-probe? | | | | |
| | TAS | `fw_ready` start | | | | |
| | TAS | `fw_ready` end | | | | |
| | ASoC | first hw_params :8 | | | | |
| | ASoC | first trigger :8 | | | | |

Store rows in `validation/phase5-resume-timeline.csv` (see template).

---

## Collection (no kernel patch yet)

Until PHASE5 kprobes/tracepoints land, use journal correlation:

```bash
./scripts/phase5-resume-collect.sh --notes "trace-N"
```

Parses existing `ENZOPLAY` / PM lines + px13 timestamps into timeline CSV.

---

## Success criteria

- ≥5 resumes with **complete** timeline to first `:8` hw_params
- Clear answer: **`fw_ready` runs Y/N** on resume
- If N → patch targets **driver resume callback**, not `hw_params` wait
- If Y but fw_ok=0 → patch targets **bus ordering** or **FW reload path**
