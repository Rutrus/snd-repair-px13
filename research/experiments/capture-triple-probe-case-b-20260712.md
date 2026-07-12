# Capture triple probe — Case B (2026-07-12)

English (canonical). Post-S2 Phase A, px13 off. Output: `validation/capture-probe-20260712-143221/`

Protocol: [capture-stream-classification-protocol.md](capture-stream-classification-protocol.md)

---

## Classification: **Case B**

All capture paths fail. **Not** RT721-only (A) or DMIC-only (C).

| Device | Path | Result | Failure mode |
|--------|------|--------|--------------|
| `hw:1,1` | RT721 jack | **FAIL** | EIO on `pcm_read` (stream opened) |
| `hw:1,3` | SmartAmp capture | **FAIL** | `hw_params` install / prepare **-EINVAL** |
| `hw:1,4` | ACP DMIC | **FAIL** | EIO on `pcm_read` |

Playback runtime still **PASS** (`func_playback_hw12=1` on same boot cycle).

---

## Kernel signals (14:32:21)

### RT721 / SDW program (hw:1,1 path)

All prepare/program steps **ret=0**:

```text
rt721 slave_port OK dir=1
amd_xport OK port=3
sdw_program_params ret=0 stream=subdevice #0-Capture
```

Then userspace **EIO** on read — runtime DMA/IRQ, not program failure.

### SmartAmp capture (hw:1,3) — **new explicit error**

```text
sdw_prepare_stream: subdevice #0-Capture: inconsistent state state 0
SDW1-PIN4-CAPTURE-SmartAmp: ASoC error (-22): at snd_soc_link_prepare()
sdw_deprepare_stream: subdevice #0-Capture: inconsistent state state 0
```

Capture stream state machine wrong after resume — **state 0** at prepare.

### DMIC (hw:1,4)

EIO on read (same class as RT721 runtime). DMIC is not ACP-isolated failure (Case C ruled out).

---

## Interpretation

```text
Playback post-S2   →  SDW playback path OK (W1+W2)
Capture post-S2    →  shared failure
  ├─ SDW capture streams: bad state / prepare EINVAL (SmartAmp)
  ├─ RT721 capture: program OK, read EIO
  └─ DMIC: read EIO (downstream of bus/DMA?)
```

**Focus:** SoundWire **capture direction** stream lifecycle after system sleep — `sdw_prepare_stream` / stream state, not RT721 codec alone, not UCM/PW.

W2 fixed TAS2783 **playback** FW reinit; **capture** substreams may not be reinitialized symmetrically.

---

## PCM status post-probe

All `pcm*c/sub0/status` → **closed** (probes exited before concurrent hang witness).

---

## Next

1. **Concurrent witness** during `arecord -D hw:1,1 -d 30` — `hw_ptr` / IRQ 160 series
2. **Trace** `sdw_prepare_stream` capture state vs playback on same boot post-S2
3. **Compare** stream state after resume: playback substream vs capture substream in SDW core
4. Do **not** extend W2 playback hooks — new work targets **capture stream reinit** or SDW manager capture port after S2

---

## References

- Prior play+cap EIO: [phase-a-topology-vs-functional-20260712.md](phase-a-topology-vs-functional-20260712.md)
- SDW prepare instrumentation: [../pcm-hwparams-code-path.md](../pcm-hwparams-code-path.md)
- Phase6 baseline inconsistent state: `validation/phase6-runs/baseline-20260710-010620/`
