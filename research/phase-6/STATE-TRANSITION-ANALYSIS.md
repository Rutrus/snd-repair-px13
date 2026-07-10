# State transition analysis — protocol

## Three chronologies (not one)

Capture and compare **separately**, then merge by `offset_ms` for diff.

### 1. Hardware (inferred from kmsg + sysfs)

```
resume → PCI/ACP → SDW master → RT721 → TAS2783 → Attached/Unattached
```

Layer tag: `hardware` in `validation/phase6-events.csv`

### 2. Kernel (PM + driver)

```
PM callbacks → runtime PM → attach → fw reload → hw_params → trigger
```

Layer tag: `kernel`

### 3. Userspace

```
resume → udev → PipeWire → WirePlumber → px13 → ALSA open → speaker-test
```

Layer tag: `userspace`

**Critical:** kernel PASS + userspace FAIL is a valid outcome (run 0001 @0–1s: Speaker visible, bus already dead).

---

## STREAM READY (`pcm_running`)

Fourth metric beyond attach / fw / speaker:

```
PCM open → hw_params → prepare → trigger → RUNNING
```

Detection (no kernel patches):

| Signal | Source |
|--------|--------|
| `RUNNING` | `/proc/asound/card1/pcm0p/sub0/status` |
| `playback without fw` | kmsg → **not** ready |
| `ENZOPLAY trigger` / `snd_pcm_start` | kmsg → likely running |

Formal PASS requires `pcm_ready=YES` (RUNNING), not merely Speaker in wpctl.

---

## Composite severity

```
PASS  — all five YES at t=60s sample
FAIL  — pm=FAIL and attach=NO (hard branch)
WARN  — partial (e.g. Speaker UI but pcm not running)
```

---

## Protocol

```bash
./scripts/phase6-experiment.sh baseline
./scripts/phase6-experiment.sh arm --notes run-N
systemctl suspend
# wait ≥65s
./scripts/phase6-experiment.sh status
./scripts/phase6-experiment.sh diagram 0001
```

After PASS + FAIL runs:

```bash
./scripts/phase6-experiment.sh diff PASS_RUN FAIL_RUN
```

**Rule:** first diverging event ends investigation for that pair — do not over-interpret downstream noise.

---

## Auto diagram

Each run generates `validation/phase6-runs/run-NNNN/diagram.txt`:

```
resume (anchor 0 ms)
 │
 ├──── +    0 ms  [hardware  ] rt721 init timeout
 ├──── +    0 ms  [kernel    ] RT721 PM -110
 ├──── + 3000 ms  [kernel    ] playback without fw
 ...
```

---

## Maintainer narrative template

> After s2idle suspend, ProArt PX13 audio resume bifurcates into two stable states. The first observable divergence occurs at **+N ms** (**event**). Downstream TAS2783 FW errors are unreachable when slaves remain Unattached. Proposed fix belongs in **layer X**, not amplifier FW reload.

---

## Artifacts

| File | Content |
|------|---------|
| `phase6-chronology.csv` | Sampled metrics per offset |
| `phase6-events.csv` | Three-layer event stream |
| `phase6-runs/run-*/diagram.txt` | ASCII timeline |
| `resume-matrix.csv` | One composite row per run |
