# Experiment — dual-path hw_params trace (2026-07-12)

English (canonical). **Q1 closed** on this run.

**Machine:** ProArt PX13 · kernel `7.0.0-27-generic`  
**Tool:** `sudo resolution/scripts/pcm-hwparams-trace.sh --dual-path`  
**Logs:** `/var/log/snd-repair/pcm-trace-S0-20260712T095812.log`, `pcm-trace-S2-20260712T100037.log`

---

## Procedure

```bash
sudo resolution/scripts/pcm-hwparams-trace.sh --label S0 --dual-path
sudo resolution/scripts/s2-reproduce.sh          # W2 S2 reproduced
sudo resolution/scripts/pcm-hwparams-trace.sh --label S2 --dual-path
```

---

## S0 (clean boot)

| Check | Result |
|-------|--------|
| Pre-witness pcm0 / pcm2 | pass / pass |
| dmesg during probes | (no driver errors) |
| Format matrix pcm2 | S16_LE 48k/44.1k 2ch PASS |

Baseline valid.

---

## S2 (post-resume) — demonstrated chain

### Pre-witness

| PCM | Class |
|-----|-------|
| pcm0 | open_ok |
| pcm2 | other (not pass) |

### Probe PCM0 (`hw:1,0`) — dmesg (filtered)

```text
slave-tas2783 sdw:…:01:8: fw download wait timeout in hw_params
slave-tas2783 sdw:…:01:8: error playback without fw download
ASoC error (-22): at snd_soc_dai_hw_params() on tas2783-codec
ASoC error (-22): at __soc_pcm_hw_params() on SDW1-PIN1-PLAYBACK-SmartAmp
…
rt721-sdca … ENZODBG slave_port OK
amd_sdw_manager … master_port OK
soundwire … sdw_program_port_params OK
```

**Note:** Opening SimpleJack still exercised **SmartAmp / tas2783 :8** link (coupled machine graph or shared stream teardown). Control-group interpretation needs `--skip-pre-witness` or probe-order experiments — does not change Q1 site.

### Probe PCM2 (`hw:1,2`)

```text
Dispositivo o recurso ocupado  (EBUSY)
```

Prior pcm0 probe left SmartAmp path busy — script should drop PCM between probes.

### Format matrix pcm2

All `fail(1)` — consistent with EBUSY after pcm0 probe, not fresh EINVAL sweep.

---

## Q1 answer (demonstrated)

| Question | Answer |
|----------|--------|
| First rejecting layer | **Codec DAI** — `tas2783-codec` |
| Function | **`tas_sdw_hw_params()`** in `tas2783-sdw.c` |
| Mechanism | `fw download wait timeout` → `!fw_dl_success` → `-EINVAL` (-22) |
| UID | **`:8`** (left SmartAmp) |

**Ruled out on this run:**

- PipeWire / Dummy (direct ALSA)
- ALSA core / `soc_pcm_check_hw_cfg` (no matching-formats message)
- Capability shrink (S0/S2 dump identical: S16, 48k, 2ch)
- Dead SoundWire bus (master_port / sdw_program_port_params OK after failure)

**Secondary lines (consequences, not primary cause):**

- `SDW: Invalid device for paging :0` — after failed FW path
- `sdw_deprepare_stream: inconsistent state state 6` — abort cleanup

---

## Q2 (open — next)

> Why does `tas2783_fw_ready()` not set `fw_dl_success` before `hw_params`?

See [../tas2783-fw_dl_success-map.md](../tas2783-fw_dl_success-map.md).

Leading inference: **`fw_dl_task_done` never becomes true** — async FW completion not reached after resume (completion path). Coherent with Phase 6–8 IRQ/enumeration gap — **not proven in same boot correlation yet**.

---

## Next steps

1. Build/install **series B 0003** (`tas2783_fw_reinit` on suspend/resume) + repeat S0/S2 trace.
2. Same boot: `phase6-hunt.sh post-suspend` + trace — correlate IRQ witness with `:8` timeout.
3. Script: PCM drop / `--probe-order pcm2-first` / `--skip-pre-witness`.

---

## Related

- [../UNIFIED-CAUSAL-MODEL.md](../UNIFIED-CAUSAL-MODEL.md)
- [../pcm-s2-set-params-witness.md](../pcm-s2-set-params-witness.md)
