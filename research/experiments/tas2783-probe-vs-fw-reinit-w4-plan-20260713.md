# TAS2783 probe vs fw_reinit — driver audit and W4 plan (2026-07-13)

English (canonical). Follows E1 discrimination: **jack OK, internal speakers silent post-S2**.

Evidence: `validation/jack-vs-speaker-20260713-103756`, witness `20260713-095125`.

---

## Domain isolated

| Layer | Post-S2 |
|-------|---------|
| SoundWire, ACP, DMA, PCM hw_ptr | OK |
| PipeWire, RT721, jack | OK |
| TAS2783 FW download (`fw_ok=1`) | OK |
| TAS2783 → physical speakers | **FAIL** |

Investigation focus: **TAS2783 resume/reinit path only.**

---

## Cold boot vs S2 — what the driver actually does

### Cold boot (first time)

```text
tas_sdw_probe()
  → regmap (cache-only), tas_init()
  → snd_soc_register_component(DAPM widgets, routes)

tas_update_status(ATTACHED)  [first attach]
  → tas_io_init()

tas_io_init()
  → SW reset
  → request_firmware → tas2783_fw_ready()  [FW chunks via sdw_nwrite]
  → tas2783_update_calibdata()
  → sdca_regmap_write_init() OR tas2783_init_seq[]  [includes PPU21 power]

First playback stream:
  → tas_sdw_hw_params()
  → tas_clear_latch()
  → PDE23 SDCA power ON (retry loop)
  → sdw_stream_add_slave() + port_prep()
  → DAPM powers widgets (FU21/FU23/SPK…) from OFF → POST_PMU → FU_MUTE=0
```

### After S2 (W2 `force_fw_reinit`)

```text
tas2783_sdca_dev_system_suspend()
  → hw_init=false, fw flags cleared

tas2783_sdca_dev_resume() / tas_update_status(ATTACHED)
  → tas2783_fw_reinit()
  → tas_io_init()   [same FW + init_seq path as cold attach]

Device does NOT unbind — no second tas_sdw_probe, no component re-register.

Playback (same as cold):
  → tas_sdw_hw_params()  [PDE23, stream, port_prep still called]
  → DAPM may believe widgets already powered (no full cold power cycle)
```

### `tas2783_fw_reinit()` today (entire function)

```c
tas_dev->hw_init = false;
tas_dev->fw_dl_task_done = false;
tas_dev->fw_dl_success = false;
return tas_io_init(dev, slave);
```

**Nothing else.** No DAPM replay, no explicit widget teardown/rebuild, no `component` re-probe.

---

## Gap hypothesis (matches symptoms)

| Hypothesis | Mechanism |
|------------|-----------|
| **Stale DAPM** | Chip reset + FW reload; ASoC software still thinks FU21/FU23/SPK ON. POST_PMU may not re-fire needed side effects. |
| **FW loaded ≠ DSP RUN** | `fw_dl_success=1` after `sdw_nwrite`; DSP may need init_seq + DAPM + PDE/PPU sequence in specific order. |
| **init_seq insufficient after reload** | `tas2783_init_seq` runs in `tas_io_init`, but **without** cold DAPM ordering; power stages (PPU21 in seq, PDE23 in hw_params) may not match hardware state machine after partial resume. |
| **PDE23 write fails silently** | hw_params retries PDE23; worth readback post-S2 vs cold. |

W3 Exp A weakened **FU_MUTE-only** theory (POST_PMU fires). Stale DAPM + missing **non-FU** init steps remain open.

---

## What NOT to pursue

- SoundWire master, ACP, RT721 (exonerated by E1)
- PipeWire / UCM / generic mixer toggles
- W3 generic `dapm_sync` as first W4 (deprioritized; try only if register diff inconclusive)

---

## W4 plan — register-level diff, then targeted restore

### E2 result (2026-07-13) — ALSA layer exonerated

Snapshots: `validation/tas2783-state-pass-cold-20260713-112648` vs
`validation/tas2783-state-fail-silent-s2-20260713-112812`.

**Diff is empty for all userspace-visible state:**

- `amixer-contents`, `amixer-scontents`, `amixer-key-controls`, `wpctl` — **identical**
- `dapm-full.txt` — unavailable (debugfs); no kernel DAPM contrast yet
- Only deltas: `suspend_count`, W2 logs, `pcm2p` RUNNING (witness timing)

**Conclusion:** investigate TAS2783 chip-private state only. W4-trace is the next action.

### Step 1 — SDCA/control readback snapshots (no kernel patch)

Already have `tas2783-state-snapshot.sh`. Extend with **readback** of key controls if exposed:

- PDE23 power state
- PPU21 (in init_seq)
- FU21/FU23 mute
- tas2783 amp/speaker mixer values

```bash
# Cold boot (speakers audible):
./scripts/tas2783-state-snapshot.sh --label pass-cold

# Post-S2 (speakers silent, jack OK):
./scripts/tas2783-state-snapshot.sh --label fail-silent-s2

diff -ru validation/tas2783-state-pass-cold-* validation/tas2783-state-fail-silent-s2-*
```

Run **during or immediately after** first speaker playback attempt.

### Step 2 — Kernel lifecycle + SDCA trace (W4-trace patch) — **ready**

Patch: `research/make-it-work/patches/w4-tas2783-trace.patch`
Build: `sudo ./scripts/build-w4-trace.sh`
Protocol: `research/experiments/w4-tas2783-trace-protocol.md`

Ordered `W4 ctx=life seq=N` counter + register readback at `io_init_out`, `fw_ready_out`, `hw_params_out`.
Optional `w4_sdca_trace=1` for every write.

### Step 3 — Lifecycle trace (W4-trace) — merged into Step 2

Log function entry at:

- `tas_io_init`, `tas2783_fw_ready`, `tas2783_fw_reinit`
- `tas_sdw_hw_params`, `tas_port_prep`
- `tas_fu21_event`, `tas_fu23_event`
- `tas2783_sdca_dev_resume`, `tas_update_status`

Compare call graphs: cold vs S2.

### Step 4 — Targeted fix (not generic dapm_sync)

Once Step 1/2 finds delta, W4 production patch does **exactly** that:

Examples (hypothetical until diff proves):

- Re-run `tas2783_init_seq` + force PDE23 in `tas2783_fw_reinit` success path
- Call `snd_soc_dapm_sync` **only if** trace shows DAPM widgets ON but readback shows power off
- Explicit DSP start register if found in TI docs / cold-only writes

---

## TI two-state model (to verify)

```text
Firmware downloaded (fw_ok=1)  ≠  DSP/analog path RUN
```

Verify with readback of power entities after fw_reinit:

- `TAS2783_SDCA_ENT_PPU21` (init_seq)
- `TAS2783_SDCA_ENT_PDE23` (hw_params)
- Vendor page registers in `tas2783_init_seq` (0x00800xxx)

---

## Immediate next actions

1. ~~**E2 snapshots**~~ — done; ALSA identical PASS vs FAIL
2. ~~**W4 lifecycle trace**~~ — done; lifecycle + readback identical at playback
3. **`sudo ./scripts/build-w4b-write-trace.sh && reboot`** — phased write trace (W4b)
4. **W4c write diff** — `./scripts/w4-write-trace-diff.sh` PASS vs FAIL playback window
5. **W5 double fw_reinit** — `./scripts/w5-double-fw-reinit-test.sh` post-S2 silent
6. **W4-fix patch** — first proven write delta or warm-boot sequence from W4b/W5

---

## References

- Driver: `linux-source-7.0.0/sound/soc/codecs/tas2783-sdw.c`
- [silent-resume-tas2783-runtime-state-20260713.md](silent-resume-tas2783-runtime-state-20260713.md)
- [w3-experiment-a-20260712.md](w3-experiment-a-20260712.md)
