# State transition analysis — protocol

## Goal

Build two **millisecond-relative chronologies** (PASS and FAIL) from the same resume anchor:

```
PM: suspend exit  →  offset_ms = 0
```

Find the **first line that differs** between them. That transition is the bug.

---

## Example (illustrative)

### FAIL (boot #40 pattern)

| offset_ms | layer | event |
|-----------|-------|-------|
| 0 | PM | suspend exit |
| ~0 | kernel | rt721 init timeout |
| ~0 | kernel | PM -110 rt721, :8, :b |
| ~0 | SDW | unattached :8 :b |
| 14000 | userspace | playback without fw (:8) |
| 33000 | px13 | PCI reset |
| 35000 | SDW | probe, still unattached |
| 60000 | userspace | Dummy Output |

### PASS (target pattern)

| offset_ms | layer | event |
|-----------|-------|-------|
| 0 | PM | suspend exit |
| ~0 | kernel | rt721 resume OK (or -110 then recovery) |
| 64 | SDW | attached :8 |
| 212 | kernel | fw_ready_done :8 |
| 3000 | userspace | PipeWire stream OK |
| 60000 | composite | PASS |

**First divergence** in this sketch: rt721 outcome at ~0–60ms.

---

## Capture protocol

### Prerequisites

- Healthy boot: `:8` Attached, `fw_ok=1`, Speaker in wpctl.
- **No kernel patches** during Phase 6 collection window.

### Steps

```bash
./scripts/phase6-experiment.sh baseline --notes boot41-pre
./scripts/phase6-experiment.sh arm --notes boot41-pass-candidate
systemctl suspend
# wait ~65s
./scripts/phase6-experiment.sh status
```

Repeat until `validation/resume-matrix.csv` shows at least one **PASS** and one **WARN** composite row.

### Sample offsets (seconds)

`0 · 0.5 · 1 · 2 · 3 · 5 · 10 · 20 · 30 · 60`

Per sample: attach (sysfs), fw (kmsg since resume), wpctl, pipewire, runtime PM, optional speaker-test.

### Kernel chronology (automatic)

After each run, `phase6-chronology-capture.sh` parses kmsg since resume into `validation/phase6-kmsg-events.csv` with patterns:

| Pattern | component |
|---------|-----------|
| `PM: suspend exit` | PM |
| `rt721.*Initialization not complete` | rt721 |
| `failed to resume: error -110` | PM |
| `update_status_attached\|unattached` | tas2783 |
| `tas_io_init\|fw_ready` | tas2783 |
| `px13-audio-fix:` | px13 |
| `playback without fw` | tas2783 |
| `binding PCI` | px13 |

---

## State graph

Maintain `validation/phase6-state-graph.csv`:

```csv
node,description
BOOT,Clean boot
ATTACHED,SDW slave Attached
FW_READY,fw_ok=1
SPEAKER,wpctl Speaker sink
DUMMY,Dummy Output
```

Transitions (`validation/phase6-state-transitions.csv`):

```csv
from,to,trigger,offset_ms,run_id,evidence
RESUME,PM110,rt721 timeout,0,0040,journal:...
PM110,UNATTACHED,bus drop,61,0040,sysfs+PHASE5
...
```

Populate from chronology — not by hand-waving.

---

## PASS composite (unchanged from Phase 5 bifurcation)

```
PASS = pm_ok ∧ uid8_attach ∧ uid8_fw ∧ speaker_present ∧ speaker_test_ok
```

kmsg-clean alone → **WARN**.

---

## Compare two runs

```bash
./scripts/phase6-chronology-diff.sh run-0001 run-0002
```

Reports:

1. First offset where `uid8_attach` differs
2. First kmsg event present in one run only (by `offset_ms` bucket)
3. Suggested hypothesis (H1–H4)

---

## Framework instrumentation (later, optional)

On this kernel (`7.0.0-27`), `tracefs/events/soundwire/` is **empty**. Options:

1. `dynamic_debug` on `soundwire/*`, `snd_*`, `regmap*` (requires root)
2. **Minimal** RT721 PHASE6-style trace patch — **only after** kmsg diff pinpoints rt721 window
3. ftrace function graph on `sdw_*` — high overhead, one-shot captures

Run `./scripts/phase6-trace-probe.sh` before planning trace patches.

---

## Upstream narrative

Phase 6 output should read as a **state machine with evidence**, not a log dump:

> After system suspend, ACP70 SoundWire resume has two stable outcomes. The first diverging transition occurs at X ms (rt721 init). Subsequent TAS2783 FW failures are unreachable when slaves remain Unattached.

That framing is maintainer-ready once backed by two full chronologies.
