# Technical diagnosis — ASUS ProArt PX13 (AMD ACP70 / SoundWire)

> **English** | [Español](es/informe-experto.md)

> **Writing criterion:** a distinction is made between **facts demonstrated by traces**, **facts verifiable in code**, and **probable interpretation**.
>
> **Maintainer-style synthesis:** [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md) — facts vs hypotheses, upstream strategy (recommended for reviewers).
>
> **Status 2026-07-09:** Problem A resolved (0004). Problem B resolved experimentally (0006+0007, Boot 7). Problem C resolved with 0009 (stereo L/R validated).

---

# Current diagnostic status

Investigation by **hypothesis elimination**: each phase narrows the search space. The current focus is on the **ASoC playback layer**, with multicodec routing to the second TAS2783 as the leading hypothesis (**H1**), but still pending experimental confirmation.

## Problem A — Incorrect capture open on TAS2783

**Status:** ✅ Resolved experimentally (patch **0004**; mechanism demonstrated by traces).

| Demonstrated evidence | Value |
|--------------------|-------|
| `Program transport params failed: -22` | Yes (pre-0004) |
| `sdw_get_slave_dpn_prop() == NULL` | Yes |
| Requested port | `port = 2`, capture |
| TAS2783 DisCo (runtime) | Only `sink_ports` (playback) |
| RT721 | Correct `source_ports` |

**Conclusion (log ↔ code linkage):**

> The capture stream attempted to incorporate a TAS2783 that, according to DisCo properties discovered at runtime, only exposes `sink` ports for playback. The absence of a `source_dpn_prop` for `port=2` causes `-EINVAL` to be returned from `sdw_get_slave_dpn_prop()`.

---

## Problem B — SmartAmp firmware download

**Status:** ✅ Resolved **experimentally** via patches **0006 + 0007** (confirmed in Boot 7).

| Phase | Log |
|------|-----|
| Before | `FW download failed: -110`, `playback without fw download` |
| After (Boot 7) | FW OK on `:8` and `:b`, no warnings |

**Conclusion:**

> After Boot 7, firmware download **no longer appears to be the source of the observed playback problem** (left channel audible, right channel mute).

**Nuance (not yet demonstrated):**

- Whether the 0006+0007 fix is fully general for all TAS2783/SDW hardware.
- Whether both DSPs are configured correctly after load, or simply stop failing on the bulk write.

Expand the reboot matrix before presenting 0006+0007 as a definitive upstream fix.

---

## Problem C — Only the left channel plays

**Status:** 🎯 **Active** — the only remaining blocker for full stereo.

| Demonstrated fact | Status |
|------------------|--------|
| Both TAS2783 enumerated | ✅ |
| Both load firmware without error (Boot 7) | ✅ |
| SDW pipeline functional | ✅ |
| Audible audio (mono / left) | ✅ |
| Right channel audible | ❌ (the opposite not demonstrated) |

**Conclusion:**

> The remaining problem belongs to the **ASoC playback phase** and not to SoundWire bus initialization or amplifier firmware (in the Boot 7 scenario).

---

## What is ruled out — and what is not

### With sufficient evidence to rule out as the cause of `-22` / SDW transport

- SoundWire enumeration
- DisCo discovery (as the origin of the port programming error in capture)
- `soundwire_amd` as the origin of `-22` (ENZODBG instrumentation)
- `transport_params` calculation on the AMD path
- ACPI matching (correct enumeration of all three slaves)
- PipeWire / WirePlumber as the origin of the SDW failure

### More conservative formulation (Problem B / playback)

Do not write "firmware download ruled out" in absolute terms. Prefer:

> Firmware download **no longer appears to be the source of the observed playback problem** after Boot 7.

It remains open whether the firmware configures both DSPs identically/correctly for stereo.

### Not ruled out 100%

- **SoundWire hardware** as the cause of the right mute (low probability; see **H4**)
- Post-FW configuration of the right DSP

---

## Active hypotheses (Problem C)

None demonstrated yet. Explicit priority:

| ID | Hypothesis | Probability |
|----|-----------|--------------|
| **H1** | ASoC multicodec routing (`soc_sdw_utils`, `acp-sdw-legacy-mach`, `codec_info_list`) | **High** |
| **H2** | Second TAS2783 does not participate in the playback stream (`probe → FW OK → hw_params → no trigger`) | Medium |
| **H3** | Incorrect `ch_mask` / channel map assignment (same channel to both amps) | Medium |
| **H4** | Physical right-channel problem (speaker / wiring) | Low — not ruled out until cross-test |

### H1 — ASoC multicodec routing

Review points: `soc_sdw_utils.c`, `acp-sdw-legacy-mach.c`, `codec_info_list`, `ch_mask` in `tas2783-sdw.c`.

### H2 — Second codec without runtime participation

```text
probe → FW OK → hw_params → (no trigger)
```

### H3 — PCM channel misassigned

```text
PCM L → Left Amp
PCM L → Right Amp
```

### H4 — Right-channel hardware

Included for methodological rigor; rule out with audible `speaker-test -s 2` or physical swap if possible.

---

## What remains to be demonstrated

| Question | Required evidence |
|----------|---------------------|
| Do both codecs receive `hw_params()`? | Instrumentation in `tas2783-sdw.c` |
| Do both receive `trigger()`? | ASoC / codec instrumentation |
| Do both receive the same `ch_mask`? | Instrumentation in `soc_sdw_utils` / `stream.c` |
| Does the second codec receive PCM samples from channel R? | `speaker-test -s 1/-s 2` + simultaneous traces |

It is still **unknown** whether `tas2783-2` (`:b`, Right): (1) does not receive PCM, (2) receives PCM but the wrong channel, or (3) receives the correct channel but never reaches `trigger()`.

---

## Priority experiment

**Do not add patches** until this check is complete.

### Why `speaker-test -s 1` / `-s 2`

> Allows distinguishing between a **channel routing problem** (H3) and a **second-codec activation problem** (H2). If the right channel remains mute even when **exclusively** playing the right channel (`-s 2`), the focus shifts from firmware to the ASoC multicodec dailink.

```bash
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1   # L only
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2   # R only
```

Record simultaneously: `hw_params`, `prepare`, `trigger`, `stream_add_slave` on **both** UIDs (`:8` / `:b`).

| Result | Reading |
|-----------|---------|
| `-s 1` audible, `-s 2` mute | H1 or H2 favored |
| Both audible | H3/H4 less likely; review PCM device |
| Neither | Regression or wrong device |

---

## Executive summary (historical detail)

Instrumentation (`ENZODBG`) allowed precise localization of the origin of the `-EINVAL (-22)` error during SoundWire stream preparation.

**Demonstrated by traces:** the AMD SoundWire Manager subsystem (`soundwire-amd`) **is not the source of the failure**. All instrumented manager functions complete with `ret=0`.

**Demonstrated by traces:** the error occurs on the slave port programming path (`soundwire-bus`), specifically when `sdw_get_slave_dpn_prop()` returns `NULL` for the TAS2783 on a capture stream.

**Demonstrated by traces (historical):** DSP firmware might not be loaded before `hw_params()` (`error playback without fw download`).

**Boot 7 update:** mitigated with 0006+0007; no longer blocks on successful boots.

---

# Part I — Demonstrated facts (ENZODBG instrumentation)

## 1. AMD SoundWire Manager ruled out

Traces in `amd_sdw_transport_params()` and `amd_sdw_port_params()`:

```text
ENZODBG[4] amd_xport OK … ret=0
ENZODBG[5] amd_port OK … ret=0
ENZODBG[5] master_port OK … ret=0
```

**Demonstrated conclusion:**

- ACP70 (`rev=0x70`) on a valid path.
- AMD master transport and port programming correct.
- The AMD manager does not generate the observed `-EINVAL` in `Program transport params failed`.

---

## 2. Exact localization of `-EINVAL`

Demonstrated chain:

```text
sdw_program_port_params()
    └── sdw_program_slave_port_params()
            └── sdw_get_slave_dpn_prop()
                    └── return NULL
                            └── -EINVAL (-22)
```

Runtime identification:

| Field             | Demonstrated value            |
| ----------------- | --------------------------- |
| Codec             | TAS2783 (`sdw:…:01:8`)      |
| `devnum`          | 2                           |
| Direction         | Capture (`dir=1`)           |
| Requested port    | 2                           |
| Stream            | `subdevice #0-Capture`      |

Traces:

```text
ENZODBG[3] slave_port FAIL … devnum=2 port=2 dir=1 dpn_prop NULL
ENZODBG[6] sdw_program_params ret=-22 stream=subdevice #0-Capture
Program transport params failed: -22
```

---

## 3. Immediate cause (demonstrated)

During **capture** stream preparation, the bus attempts to resolve DPN properties for **port 2** in TX direction (capture).

The TAS2783 DisCo (previously verified in sysfs) advertises:

```text
sink_ports = 0x2   → DP1 (playback)
source_ports       → (absent / 0)
```

Therefore `sdw_get_slave_dpn_prop()` does not find `src_dpn_prop` for port 2 → `NULL` → `-EINVAL`.

**This is the immediate cause of the error**, not an inference.

---

## 4. What the traces demonstrate collectively

| Aspect                         | Status        |
| ------------------------------- | ------------- |
| SoundWire enumeration           | OK            |
| Slave response                  | OK            |
| AMD Manager                     | OK            |
| TAS2783 playback (DP1, dir=0)   | OK            |
| RT721 playback                  | OK            |
| RT721 capture (DP2)             | OK            |
| TAS2783 capture (DP2)           | **FAIL**      |

---

## 5. Second problem (firmware — historical; resolved Boot 7)

```text
error playback without fw download
ASoC error (-22) at snd_soc_dai_hw_params() on tas2783-codec
```

Indicates `fw_dl_success == false` in the codec driver when ALSA runs `hw_params()`.

**Independent** of the `dpn_prop NULL` capture failure. Both must be resolved for fully functional audio.

---

# Part II — What traces alone do not demonstrate

## Demonstrated chain (failure mechanism)

```text
ALSA opens capture stream
    ↓
TAS2783 receives hw_params(capture)          ← what triggers it: NOT demonstrated by traces
    ↓
port_config.num = 2
    ↓
sdw_stream_add_slave()
    ↓
sdw_program_slave_port_params()
    ↓
sdw_get_slave_dpn_prop() → NULL
    ↓
-EINVAL
```

**Do not claim:** *"the root cause is a topology bug"* — that is not demonstrated.  
**Do claim:** there is a **mismatch** between what the stream requests (DP2 capture) and what DisCo advertises (sink DP1 only).

## Who made the wrong decision — three scenarios (not demonstrated)

| Scenario | Component | Probability |
|-----------|------------|--------------|
| 1 | `tas2783-sdw`: DAI with `.capture` + `port=2` in `hw_params` | Very likely (verifiable in code) |
| 2 | Machine / `sdw_utils`: TAS2783 on capture dailink (`.direction = {true,true}`) | Possible (verifiable in code) |
| 3 | ASoC creates full-duplex stream for playback-only codec | Less likely |

### Code evidence (does not replace traces)

```text
sound/soc/codecs/tas2783-sdw.c
    → snd_soc_dai_driver: .capture present
    → tas_sdw_hw_params(): port=2 on capture

sound/soc/sdw_utils/soc_sdw_utils.c
    → codec_info_list[tas2783]: .direction = {true, true}
```

An upstream maintainer would ask: *why does `hw_params(capture)` reach here?* — that question remains open.

---

# Part III — Problem architecture

```text
                 Playback
                     │
      RT721 ───────────────► OK (port=1, dir=0)
      TAS2783 #1 ──────────► OK (port=1, dir=0)
      TAS2783 #2 ──────────► OK (port=1, dir=0)
                     │
           soundwire-amd ──► OK ([4][5][6] ret=0)


                 Capture
                     │
      RT721 ───────────────► OK (port=2, dir=1)
      TAS2783 #2 ──────────► requests port=2, dir=1
                     │
        sdw_get_slave_dpn_prop()
                     │
             src_dpn_prop missing
                     │
                     ▼
                NULL → -EINVAL
```

---

# Part IV — Correction hypotheses (not definitive solution)

**Not recommended:** silencing the error in `soundwire-bus` — the framework correctly detects an inconsistency.

### Patch 0004 — experimental correction hypothesis

```c
if (capture && !source_ports)
    return 0;   /* do not join the capture stream */
```

| Aspect | Assessment |
|---------|------------|
| Utility | Eliminates the invalid flow; good experiment |
| Runtime validation | After 0004: `Program transport params failed` disappears on capture |
| Upstream solution? | **Still to validate** — may not be the correct location |
| Maintainer question | *Why does `hw_params(capture)` reach here?* |

The accepted solution could be in the machine driver, ACPI/`codec_info_list`, or removing `.capture` from the DAI — not necessarily in the `hw_params` guard.

### Option A — `tas2783-sdw` (where 0004 lives)

Guard in `hw_params` / review `.capture` in the DAI.

### Option B — machine / `sdw_utils`

`.direction = {true, false}` for TAS2783; speaker dailink playback-only.

### Problem B — firmware (resolved in Boot 7 with 0006+0007)

Independent of Problem A. Historical symptom:

```text
FW download failed: -110   (intermittent on :b, ~50% boots)
playback without fw download (:8 WARN due to async race)
```

**Current status:** Boot 7 — both UIDs OK; 0006 (retry nwrite) + 0007 (wait in hw_params) applied. **Experimental** — confirm with expanded matrix.

**Problem C — stereo routing** replaces firmware as the investigation focus (see Part VIII).

---

# Part VII — Reboot matrix and problem separation (Jul 2026)

## Methodology

Script `scripts/collect-tas2783-fw.sh` after each reboot; correlation with `speaker-test -D plughw:1,2 -c 2`.

ACPI mapping (demonstrated in `amd-acp70-acpi-match.c`):

| SDW UID | ACPI prefix | Physical channel |
|---------|--------------|--------------|
| `0x8` | `tas2783-1` | Left |
| `0xb` | `tas2783-2` | Right |

---

## Consolidated matrix (7 boots)

| Boot | `:8` Left | `:b` Right | Reported audio |
|------|-----------|------------|-----------------|
| 1 | WARN | **FAIL(fw)** | L-only |
| 2 | WARN | OK | L-only |
| 3 | WARN | OK | L-only |
| 4 | WARN | **FAIL(fw)** | L-only |
| 5 | WARN | **FAIL(fw)** | L-only |
| 6 | WARN | OK | L-only |
| **7** | **OK** | **OK** | L-only |

### Demonstrated by the matrix (boots 1–6)

1. **`:8` never logs `FW download failed`** — the `-110` in `sdw_nwrite` affects only **`:b`** intermittently (~50%).
2. **`:8` always `WARN(no-fw-hw_params)`** in boots 1–6 — PipeWire/ALSA calls `hw_params()` before `request_firmware_nowait()` completes.
3. **L-only with `:b` = OK** (boots 2, 3, 6) — the mute right channel **does not depend exclusively** on the firmware failure at probe.

### Compatible with (not demonstrated as sole cause)

- Temporal contention in parallel FW download (loses `:b`, does not alternate UIDs on nwrite).
- PipeWire race vs async firmware callback on `:8`.

### Not compatible with

- Deterministic `FW download failed` failure for the same UID on every boot (`:8` never fails nwrite).
- Deep bug in `soundwire-amd` or SDW transport.

---

## Boot 7 — change in problem nature

**Boot 7** (`boot_id=686521be`, after patches **0006 + 0007**):

```text
:8 = OK
:b = OK
(no FW download failed, no playback without fw download)
```

### What Boot 7 demonstrates

1. **Both TAS2783 alive:** respond on SDW, accept firmware, DSP initialized.
2. **Initialization no longer blocks playback** on this boot.
3. **0006 + 0007 mitigate the firmware failure on this hardware** (confirmed in Boot 7) — **experimental** fix; upstream generality to validate.
4. **The SoundWire bus is ruled out** for the FW layer in Boot 7: enumeration, attach, transport params, port params, firmware loader — all OK in that scenario.

### Important nuance

Boot 7 **separates** two causes that previously appeared mixed:

| Cause | Boots 1–6 | Boot 7 |
|-------|-----------|--------|
| FW initialization / timing | ✅ active problem | ✅ resolved |
| Multicodec stereo routing | ✅ present (L-only) | ✅ **still present** (L-only) |

**Conclusion:** with FW OK on both amplifiers and audio still L-only, the investigation **leaves codec initialization** and moves to **how ASoC builds and routes the SmartAmp dailink to the two TAS2783s**.

---

## Patches 0006 and 0007 (firmware — resolved in Boot 7)

| Patch | Mechanism | Target |
|--------|-----------|----------|
| **0006** | Retry ×5, `usleep_range(10–15 ms)` on `-ETIMEDOUT`/`-EAGAIN` during `sdw_nwrite_no_pm()` | Transient timeout on FW bulk write |
| **0007** | `wait_event` in `hw_params()` until `fw_dl_task_done` before rejecting | PipeWire race vs async download |

**Demonstrated:** Boot 7 without FW errors or `playback without fw`.  
**Not yet demonstrated:** stability over N→∞ reboots (expanding the matrix recommended).

---

# Part VIII — Problem C: multicodec stereo routing

> See **H1–H4** and the "What remains to be demonstrated" table in "Current diagnostic status".

## Symptom

- `speaker-test` / `Front Center`: **left channel only** audible.
- ALSA mixers in Boot 7: `tas2783-1/2 Speaker` = 200, `Left/Right Spk` = on — **not user mute**.

## Detailed hypotheses (↔ H1–H3)

### H1 — The right channel never enters the stream

```text
CPU DAI
    ├── TAS2783 Left   ← ch_mask OK
    └── TAS2783 Right  ← never receives ch_mask=0x2 (or mask=0x0)
```

### H3 — Both amplifiers receive the same channel

```text
PCM L ──► Left Amp
PCM L ──► Right Amp   (duplicated; Front Center would sound "mono")
```

### H2 — The second codec is not activated at runtime

Possibly incomplete chain on `tas2783-2`:

```text
probe → FW OK → hw_params → stream_add_slave → port_prep
                                              ↘ trigger() never reached
```

Dailink or ASoC configuration problem, not firmware.

---

## Next experiment (priority)

### 1. Audible L/R separation

```bash
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1   # L only
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2   # R only
```

| Result | Reading |
|-----------|---------|
| `-s 1` audible, `-s 2` mute | A or C — right outside stream or without trigger |
| Both audible | B less likely; review perception / PCM device |
| Neither | Regression or wrong device |

### 2. Traces during playback

```bash
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 &
sudo dmesg -T | grep -Ei 'tas2783|hw_params|trigger|prepare|add_slave'
cat /proc/asound/pcm
```

### 3. If right stays mute with FW OK — ASoC layer (no more FW patches)

| File | What to review |
|---------|-------------|
| `sound/soc/amd/acp/acp-sdw-legacy-mach.c` | SmartAmp dailink construction |
| `sound/soc/sdw_utils/soc_sdw_utils.c` | Multicodec stream, codec order |
| `sound/soc/codecs/tas2783-sdw.c` | `ch_mask`, `port_config`, `stream_config` |
| `codec_info_list` (tas2783) | Order `tas2783-1` / `tas2783-2`, ACPI endpoints |

Suggested instrumentation: `hw_params`, `stream_add_slave`, `trigger` on **both** UIDs with channel and `ch_mask`.

---

# Part V — Diagnostic status table (updated)

| Hypothesis | Status |
|-----------|--------|
| Defective SoundWire hardware | ❌ Ruled out |
| Incorrect enumeration / ACPI | ❌ Ruled out (enumeration OK) |
| Error in `soundwire-amd` | ❌ Ruled out (instrumentation) |
| `Program transport params failed (-22)` TAS2783 capture | ✅ Resolved (0004) |
| `sdw_get_slave_dpn_prop()` → `NULL` on capture | ✅ Mechanism demonstrated; avoided by 0004 |
| Intermittent firmware `-110` (`:b`) | ✅ Mitigated experimentally (0006+0007, Boot 7) |
| Post-FW DSP configuration for stereo | ⚠️ Not demonstrated |
| `hw_params` vs async FW race (`:8` WARN) | ✅ Mitigated (0007) |
| PipeWire → speaker chain (mono) | ✅ Functional |
| **L+R multicodec stereo routing (H1)** | 🎯 Leading hypothesis; confirmation pending |
| FW serialization mutex patch | ⏸️ Not priority after Boot 7 |

---

# Part VI — Historical evolution (updated)

| Phase | Result |
| ---- | --------- |
| Hardware / enumeration | Ruled out |
| ACPI / `snd-amd-sdw-acpi` | Ruled out |
| PipeWire / WirePlumber | Ruled out as SDW origin |
| AMD manager hypothesis | **Ruled out** (ENZODBG) |
| TAS2783 capture `-EINVAL` mechanism | **Demonstrated** (ENZODBG) |
| Patch 0004 | SDW capture OK |
| FW matrix 6 boots | `:b` intermittent; L-only persistent |
| Patches 0006 + 0007 | **FW OK both amps (Boot 7)** |
| Current investigation | **SmartAmp routing → 2× TAS2783** |

---

## Conclusion

Report structured for ALSA / AMD / TI maintainers:

| Phase | Result |
|------|-----------|
| **A** — TAS2783 capture | Identified, reproduced, isolated (0004) |
| **B** — SmartAmp firmware | Resolved **experimentally** (0006+0007, Boot 7; generality to validate) |
| **C** — multicodec stereo | Delimited; H1–H4; instrumentation pending |

For upstream:

- **0004** — capture workaround; missing `source_dpn_prop` mechanism in DisCo.
- **0006+0007** — **experimental** FW timing fix (attach boot matrix; do not claim generality).
- **Problem C** — separate thread; H1 hypothesis (ASoC routing) **pending confirmation** with `speaker-test -s 2` + traces.

The investigation relies on instrumentation, logs, and code — not intuition. The natural next step is to instrument `hw_params`, `prepare`, `trigger`, and multicodec dailink construction (**patch 0008**).

---

# Part IX — Playback instrumentation (0008, Problem C)

**Objective:** demonstrate whether `tas2783-2` (`UID :b`) participates in the ASoC pipeline.

`ENZOPLAY[N]` traces (does not fix routing):

| N | Module | Points |
|---|--------|--------|
| 1 | `snd-soc-tas2783-sdw` | `set_stream`, `hw_params`, `stream_add_slave`, `stream_remove_slave`, `port_prep` |
| 2 | `snd-soc-sdw-utils` | `asoc_sdw_hw_params` (`ch_map`), `prepare`, `trigger` |

**Phase 1 (no sudo):** `./scripts/run-stereo-phase1.sh`

**Phase 2 (sudo + reboot):** `./scripts/build-playback-instrumentation.sh`

**Decision tree:**

- `UID :b` without `hw_params` / `port_prep` → **H2**
- Both UIDs + `machine trigger` → **H1/H3**
- `ch_map[0] == ch_map[1]` with `step=0` on playback → **H3** candidate (see `asoc_sdw_hw_params()` in code)

---

# Part X — ENZOPLAY results (2026-07-09) and `ch_maps` focus

## Demonstrated by ENZOPLAY + `speaker-test` (left only audible)

### H2 — ruled out

Both TAS2783 on `SDW1-PIN1-PLAYBACK-SmartAmp`:

| UID | prefix | hw_params | stream_add_slave | port_prep | machine trigger |
|-----|--------|-----------|------------------|-----------|-----------------|
| `0x8` | tas2783-1 | OK | ret=0 | PRE ch_mask=0x3 | START/STOP |
| `0xb` | tas2783-2 | OK | ret=0 | PRE ch_mask=0x3 | START/STOP |

The second amplifier **does participate** in the full ASoC pipeline.

### H3 — demonstrated (duplicated mask)

```text
ch_map[0] ch_mask=0x3 step=0
ch_map[1] ch_mask=0x3 step=0
stream_add_slave uid=0x8 port=1 ch_mask=0x3
stream_add_slave uid=0xb port=1 ch_mask=0x3
```

Both codecs receive **L+R** (`0x3`), not L on one and R on the other.

### Code traceability (4 review points)

| # | File | Finding |
|---|---------|----------|
| 1 | `acp-sdw-legacy-mach.c` | Assigns `codec_maps[j].cpu=0`, `codec=j`; does **not** set `ch_mask` (filled at runtime) |
| 2 | `soc_sdw_utils.c` → `asoc_sdw_hw_params()` | Playback: `step=0` → same mask to all (*"Identical data will be sent to all codecs"*) |
| 3 | `tas2783-sdw.c` | `snd_sdw_params_to_config()` forces `port_config.ch_mask = GENMASK(ch-1,0)` → ignored `ch_maps` |
| 4 | `amd_manager.c` | No anomaly; master with port 1 is consistent |

### Expected vs observed model

```text
Expected:  ch0 → tas2783-1 (Left)    ch_mask=0x1
           ch1 → tas2783-2 (Right)   ch_mask=0x2

Observed:  ch0+ch1 → both amps     ch_mask=0x3
```

### Assessment after ENZOPLAY (no probability estimates)

| Finding | Status | Basis |
|---------|--------|-------|
| Duplicated `ch_map` / `ch_mask` on multicodec playback | Demonstrated | `ch_mask=0x3` on both codecs, `step=0` |
| Mechanism in `soc_sdw_utils.c` | Identified in code | Playback branch always uses `step=0` |
| TAS2783 overwrites map in `snd_sdw_params_to_config()` | Demonstrated | Code path + traces |
| Second codec outside playback stream (H2) | Ruled out | Full pipeline on both UIDs |
| Hardware fault on right channel (H4) | Ruled out for routing | 0009 + `speaker-test -s 2` |
| Internal DSP channel handling post-FW | **Not demonstrated** | Do not infer without direct evidence |

See [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md) for root-cause analysis and upstream framing.

## Experimental patch 0009 — L/R `ch_mask` split

| File | Change |
|---------|--------|
| `soc_sdw_utils.c` | If `playback && num_codecs>1 && ch==num_codecs` → `ch_maps[i].ch_mask = BIT(i)` |
| `tas2783-sdw.c` | After `snd_sdw_params_to_config`, use codec `ch_map->ch_mask` in `port_config` |

Build: `./scripts/build-playback-instrumentation.sh` (includes both modules).

**Expected verification in ENZOPLAY:**

```text
ch_map[0] ch_mask=0x1
ch_map[1] ch_mask=0x2
stream_add_slave uid=0x8 ch_mask=0x1
stream_add_slave uid=0xb ch_mask=0x2
```

---

# Part XI — 0009 validation (2026-07-09, 12:58)

## Problem C — **RESOLVED**

| Test | Auditory result | Log |
|--------|-------------------|-----|
| `speaker-test -s 1` | **Left** only | `ch_mask=0x1` uid=0x8 |
| `speaker-test -s 2` | **Right** only | `ch_mask=0x2` uid=0xb |

Full pipeline OK: `hw_params` → `prepare ret=0` → `trigger START/STOP` on both codecs.

### Mechanism established (two layers)

1. `asoc_sdw_hw_params()` assigned full stereo (`0x3`) to each codec on playback when `step=0`.
2. `tas2783-sdw.c` ignored `ch_maps` and forced `GENMASK` in `port_config.ch_mask`.
3. **0009** addresses both → L on `:8`, R on `:b` (validated audibly and in traces).

**Not claimed:** internal DSP calibration behaviour beyond successful FW load and port programming.

### Global status of all three problems

| ID | Symptom | Patch | Status |
|----|---------|--------|--------|
| A | TAS2783 capture `-22` | 0004 | ✅ Resolved |
| B | Intermittent FW download `-110` | 0006+0007 | ✅ Resolved (experimental) |
| C | Left speaker only | 0009 | ✅ **Resolved and validated** |

### Pending (does not block playback)

- `SDW1-PIN4-CAPTURE-SmartAmp`: `machine prepare ret=-22` (TAS2783 without `source_ports` on capture dailink; 0004 covers codec but not machine-level prepare).
- Remove ENZOPLAY/ENZODBG instrumentation before upstream.
- Generality of 0006/0007/0009 on other AMD/TI platforms — not demonstrated.

---

# Part XII — Upstream series (clean patches)

Maintainer-style submission strategy: [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md).

Patches without debug, organized in `./upstream/`:

| Series | Content | Submit |
|-------|-----------|--------|
| A | capture without `source_ports` | Now |
| B | FW retry + wait (RFC) | After VALIDATION-TODO |
| C | `ch_map` split + tas2783 honor mask | Now |
| D | `docs/INVESTIGATION-SUMMARY.md` | On demand |

See `upstream/README.md` and `upstream/docs/PRE-SUBMIT-CHECKLIST.md`.

---

*Last updated: 2026-07-09 — Problem C validated; upstream series prepared.*
