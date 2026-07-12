# Track PCM — SmartAmp hw_params EINVAL after resume

English (canonical). **Active investigation line** as of 2026-07-12.

**Unified model:** [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md) · **Framing:** [PCM2-investigation-framing.md](PCM2-investigation-framing.md)

Rescue/bruteforce **paused/frozen** — negative result: all rebuild paths reconverge to PCM2 `set_params` EINVAL.

---

## Questions

| # | Question | Status |
|---|----------|--------|
| **Q1 (local)** | Which function returns `-EINVAL` on hw:1,2? | **OPEN** — priority |
| **Q2 (causal)** | Why is SmartAmp state invalid after resume? | **INFERRED** — IRQ, FW, DAPM, etc. |

Do not close Q2 in upstream text until Q1 names the callback.

---

## Demonstrated facts

| Claim | Evidence |
|-------|----------|
| PCM0 PASS · PCM2 EINVAL post-resume | [pcm-s2-set-params-witness.md](pcm-s2-set-params-witness.md) |
| Natural control group | Same kernel, resume, PCI, card, process — only RT721 vs TAS2783 path differs |
| Pre-DMA failure | `set_params` rejects before first sample |
| Dummy / PipeWire not root | Direct `aplay -D hw:1,2` fails |
| PCI/rescue/bruteforce ≠ fix | remove/rescan/reload reconverge |

Historical `playback without fw download` / `:8 done=0` logs are the **same failure class** observed earlier (likely `tas_sdw_hw_params` ~906) — not a separate bug.

---

## Local cause estimates (pre-trace)

| Site | ~% | dmesg |
|------|---:|-------|
| `tas_sdw_hw_params()` | **45** | `playback without fw download` |
| `soc_pcm_check_hw_cfg()` | **30** | `No matching formats/rates/channels` |
| `sdw_stream_add_slave()` | **15** | `Unable to configure port` |
| ALSA `constrain_*` | **5** | (silent) |
| Other | **5** | — |

---

## Failure model (manifestation only)

```text
s2idle resume
    ↓
[inferred] SmartAmp / TAS2783 state not reconstructed
    ↓
snd_pcm_hw_params() on hw:1,2 → EINVAL
    ↓
Dummy Output
```

---

## Protocol

### 1–3. Baseline / S2 / witness

```bash
sudo resolution/scripts/pcm-introspect.sh --label S0
sudo resolution/scripts/s2-reproduce.sh
sudo resolution/scripts/pcm-introspect.sh --label S2
sudo resolution/scripts/witness-pcm-probe.sh
```

### 4. Format sweep

```bash
sudo resolution/scripts/pcm-introspect.sh --label S2 --sweep-only
```

### 5. Dual-path hw_params trace — **priority**

Instrument **both** PCM0 (control) and PCM2 (fail) in one run. First divergence in dmesg / call chain = highest-value artifact.

```bash
sudo resolution/scripts/pcm-hwparams-trace.sh --label S0 --dual-path
sudo resolution/scripts/s2-reproduce.sh
sudo resolution/scripts/pcm-hwparams-trace.sh --label S2 --dual-path

diff -u /var/log/snd-repair/pcm-trace-S0-*.log /var/log/snd-repair/pcm-trace-S2-*.log
sudo dmesg | rg -i 'playback without fw|Unable to configure|No matching'
```

Without `--dual-path`, script probes PCM2 only (legacy mode).

Static map: [pcm-hwparams-code-path.md](pcm-hwparams-code-path.md)

### 6. Compare S0 vs S2 introspect logs

```bash
diff -u /var/log/snd-repair/pcm-intro-S0-*.log /var/log/snd-repair/pcm-intro-S2-*.log
```

---

## Paused / frozen lines

| Line | Role in unified model |
|------|----------------------|
| Phase 6–8 | Remote cause **candidate** (IRQ boundary) — [frozen/upstream-proof/](frozen/upstream-proof/) |
| `resolution/rescue/` | Negative: rebuild ≠ fix |
| `resolution/bruteforce/` | Negative: no PASS sequence |
| Track A | Same chain — FW log altitude |

---

## Upstream value

1. Q1: rejecting function + dual-path divergence log
2. S0 vs S2 capability diff on pcm2
3. **Separate** Phase 6–8 IRQ boundary report (do not merge as proven cause of EINVAL)

---

## Related

- [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md)
- [pcm-s2-set-params-witness.md](pcm-s2-set-params-witness.md)
- [../resolution/WITNESS-QUALITY.md](../resolution/WITNESS-QUALITY.md)

