# PCM S2 witness — set_params failure on SmartAmp only

English (canonical). **2026-07-12** on ASUS ProArt PX13, kernel `7.0.0-27-generic`, post-suspend S2.

Tool: `sudo resolution/scripts/witness-pcm-probe.sh`  
Logs: `witness-pcm-20260712T022514.log` (first run, pcm index bug), `witness-pcm-20260712T022615.log` (**confirmed**)

---

## Failure chain (authoritative)

```text
s2idle resume
    ↓
snd_pcm_hw_params() rejects S16_LE 48kHz 2ch on SmartAmp PCM (hw:1,2)
    ↓
ALSA primary playback broken
    ↓
WirePlumber cannot create speaker sink
    ↓
Dummy Output (symptom — not root cause)
```

PCI remove + rescan + driver reload **does not** fix `set_params` on `hw:1,2`. Enumeration is not the blocker.

---

## Per-PCM results (card 1)

| Device | ALSA name | aplay S16_LE 48kHz 2ch | speaker-test wav | Error class |
|--------|-----------|------------------------|------------------|-------------|
| **hw:1,0** | `SDW1-PIN0-PLAYBACK-SimpleJack` rt721-sdca-aif1-0 | **PASS** | **PASS** | `open_ok` |
| **hw:1,2** | `SDW1-PIN1-PLAYBACK-SmartAmp` multicodec-2 | **FAIL** | **FAIL** | `set_params_fail` / `einval` |

### hw:1,2 stderr (representative)

```text
aplay: set_params: Imposible instalar los parámetros de hw:
ACCESS:  RW_INTERLEAVED
FORMAT:  S16_LE
CHANNELS: 2
RATE: 48000
...
```

```text
speaker-test: Falló el establecimiento de los parámetros hw: Argumento inválido
```

This is **`snd_pcm_hw_params()` failure**, not silent playback. The PCM does not accept the requested hardware configuration.

### sysfs note (2026-07-12T02:26:15)

Both PCMs show `status: closed` and `hw_params: closed` in sysfs **before and after** probe — even when `hw:1,0` aplay PASSes. ALSA closes the PCM when the process exits; on `hw:1,2` **`set_params` fails before a running stream**, so sysfs never shows negotiated params. To capture live `hw_params`, hold the device open (e.g. background `aplay`) while reading sysfs.

`subdevices_avail: 1` on both PCMs — not a subdevice-busy (`EBUSY`) case at enumeration level.

---

## Witness verdicts (coherent, 2026-07-12T02:26:15)

| Gate | Result | Notes |
|------|--------|-------|
| L1 kernel | PASS | Card + PCMs enumerated |
| ALSA primary (`hw:1,2`) | FAIL | SmartAmp path |
| ALSA any (incl. fallback) | PASS | SimpleJack `hw:1,0` opens |
| Playback strict | FAIL | Requires primary + no Dummy |
| Userspace | dummy | Consequence of primary PCM dead |

**Do not** treat `ALSA any: PASS` as recovery. Speakers route through **SmartAmp** (`hw:1,2`), not SimpleJack.

**Unified model:** [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md) · **Next:** Q1 dual-path trace — [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md)

---

## What this invalidates

| Old assumption | Status |
|----------------|--------|
| Dummy Output is root cause | **Invalid** — symptom only |
| `plughw` PASS = audio OK | **Invalid** |
| PCI remove/rescan fixes S2 | **Invalidated** on 2026-07-12 run (level D) |
| Single PASS/FAIL for "ALSA" | **Insufficient** — must probe per PCM |

---

## Next investigation (kernel-facing)

1. **Accepted formats** when broken — sysfs `hw_params` stays `closed` until a stream negotiates params; use held-open probe or `aplay -D hw:1,2 --dump-hw-params` if available.

2. **Kernel return** on `hw_params` — correlate with `dmesg` immediately after:
   ```bash
   aplay -D hw:1,2 -f S16_LE -c 2 -r 48000 -t raw -d 1 /dev/zero 2>&1 | tee /tmp/aplay-fail.txt
   sudo dmesg | tail -30
   ```

3. **DAPM / TAS2783 RUN** — SmartAmp `multicodec-2` path only; RT721 SimpleJack (`hw:1,0`) unaffected explains split PASS/FAIL.

---

## Scripts

| Script | Role |
|--------|------|
| `resolution/scripts/witness-pcm-probe.sh` | Per-PCM characterization + log |
| `resolution/scripts/witness-audio-chain.sh` | Full L1–L4 chain |
| `resolution/scripts/s2-oracle.sh` | S2 certification |
| `resolution/WITNESS-QUALITY.md` | Witness rules |

| Script | Role |
|--------|------|
| `resolution/scripts/pcm-hwparams-trace.sh` | **Priority:** dynamic_debug + single aplay + dmesg diff |
| `resolution/scripts/pcm-introspect.sh` | S0/S2 dump-hw-params + format sweep + debugfs |
| `resolution/scripts/witness-pcm-probe.sh` | Per-PCM PASS/FAIL + stderr class |

---

## Related

- [pcm-hwparams-code-path.md](pcm-hwparams-code-path.md) — kernel source EINVAL map
- [../resolution/WITNESS-QUALITY.md](../resolution/WITNESS-QUALITY.md)
- [../docs/firmware-data.md](../docs/firmware-data.md) — `hw:1,2` = TAS2783 SmartAmp
- [../docs/PROJECT-STATE.md](../docs/PROJECT-STATE.md) — H1 PM resume SmartAmp
