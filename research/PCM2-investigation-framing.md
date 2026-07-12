# PCM2 (SmartAmp) — investigation framing

English (canonical). Strategic pivot as of **2026-07-12**.

**Canonical model (facts vs inference):** [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md)

Stop thinking about **"audio"**. Think exclusively about **PCM2 (SmartAmp / `hw:1,2`)** and **which callback returns `-EINVAL`**.

---

## Demonstrated chain (manifestation)

```text
Resume
    ↓
SmartAmp / TAS2783 / ASoC state not reconstructed  ← cause: inferred (see unified model)
    ↓
snd_pcm_hw_params() on hw:1,2 → -EINVAL            ← observable fact
    ↓
PCM2 unusable
    ↓
Dummy Output (consequence — not root cause)
```

---

## Dominant fact

| Component | State |
|-----------|-------|
| PCI device | ✔ present |
| SOF | ✔ loaded |
| SoundWire | ✔ alive |
| RT721 | ✔ attached |
| TAS2783 | ✔ attached (sysfs / dmesg) |
| PCM0 (SimpleJack / `hw:1,0`) | ✔ accepts `hw_params` — **control path** |
| **PCM2 (SmartAmp / `hw:1,2`)** | ✘ `snd_pcm_hw_params()` → **`-EINVAL`** |
| PipeWire | Dummy Output (**consequence**) |

Failure is **before** DMA, playback-time IRQ, transfer, or PipeWire.

---

## Ruled out (demonstrated — see unified model F1–F5)

PCI, dead SoundWire bus, global ALSA/ACP failure, PipeWire root cause, standard re-init paths (rescue/bruteforce). **If any were truly broken, PCM0 would not open.**

---

## Active question (Q1 — local)

> Which function returns `-EINVAL` first on the SmartAmp path?

| Site | ~% (pre-trace) | dmesg hint |
|------|---------------:|------------|
| `tas_sdw_hw_params()` | **45** | `playback without fw download` |
| `soc_pcm_check_hw_cfg()` | **30** | `No matching formats/rates/channels` |
| `sdw_stream_add_slave()` | **15** | `Unable to configure port` |
| ALSA `constrain_*` | **5** | (silent) |
| Other | **5** | — |

Remote causes (IRQ, FW stale, DAPM, reinit) are **Q2** — do not state as proven until Q1 closes.

---

## Protocol (priority)

### Dual-path trace (control + fail)

```bash
sudo resolution/scripts/pcm-hwparams-trace.sh --label S0 --dual-path
sudo resolution/scripts/s2-reproduce.sh
sudo resolution/scripts/pcm-hwparams-trace.sh --label S2 --dual-path
```

Instrument **PCM0 and PCM2 in one run** — first divergence in the call chain is the highest-value artifact.

### Capability sweep (secondary)

```bash
sudo resolution/scripts/pcm-introspect.sh --label S2 --sweep-only
```

Static map: [pcm-hwparams-code-path.md](pcm-hwparams-code-path.md)

---

## Stopped

Rescue/bruteforce new sequences · Dummy chasing · "does audio work?" · treating IRQ as proven EINVAL cause.

---

## Related

| Asset | Role |
|-------|------|
| [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md) | Branch map + facts/inference |
| [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md) | Active protocol |
| [pcm-s2-set-params-witness.md](pcm-s2-set-params-witness.md) | Runtime evidence |
| [../resolution/rescue/README.md](../resolution/rescue/README.md) | **paused** |
| [../resolution/bruteforce/README.md](../resolution/bruteforce/README.md) | **frozen** |
