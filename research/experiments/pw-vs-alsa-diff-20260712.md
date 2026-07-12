# PW vs ALSA capture diff — hw:1,4 (Internal Mic / DMIC)

**2026-07-12 15:01** · post-S2 session · script: `scripts/post-s2-pw-vs-alsa-diff.sh`

Artifacts: `validation/pw-vs-alsa-diff-20260712-150144/`

---

## Question

What does PipeWire do that bare `arecord -D hw:1,4` does not?

---

## Same PCM, same path

PipeWire Internal Mic node:

```text
api.alsa.path = "hw:amdsoundwire,4"
api.alsa.open.ucm = "true"
device.profile.name = "HiFi: Mic: source"
```

UCM `Device.Mic` → `CapturePCM "_ucm0001.hw:amdsoundwire,4"`.

**Not a different device** (not plughw vs hw on another node). Both use **card1 pcm4c**.

---

## Case A — PipeWire (`pw-record`)

| Field | Value |
|-------|-------|
| WAV | **774188 B** — valid |
| access | **MMAP_INTERLEAVED** |
| format | S32_LE |
| rate | 48000 |
| period_size | **1024** |
| buffer_size | **4096** |
| status | RUNNING, **hw_ptr advancing** |

---

## Case B — default `arecord -D hw:1,4`

| Field | Value |
|-------|-------|
| WAV | **44 B** (header only) |
| Result | **EIO** on `pcm_read` |
| hw_params snapshot | closed (stream died before 1 s sample) |

Default `arecord` uses **RW_INTERLEAVED** and different period/buffer (typically period 2048, buffer 16384).

---

## Follow-up — match PipeWire params (same session, PW stopped)

```bash
arecord -D hw:1,4 -f S32_LE -r 48000 -c 2 \
  -M --period-size=1024 --buffer-size=4096 -d 2 /tmp/test-matched.wav
```

| Result | **768044 B — PASS** |

RT721 (`hw:1,1`, S16_LE, same `-M` geometry):

| Result | **384044 B — PASS** |

`alsaucm set _enadev Mic` + default `arecord` (no `-M`) → **EIO** again.

---

## First divergence (answer)

| Step | PipeWire | Default arecord | Match PW params |
|------|----------|-----------------|-----------------|
| Device | hw:1,4 | hw:1,4 | hw:1,4 |
| UCM profile | HiFi:Mic (via PW) | none | manual `_enadev` insufficient alone |
| **access** | **MMAP** | **RW** | **MMAP (`-M`)** |
| period / buffer | 1024 / 4096 | ~2048 / ~16384 | 1024 / 4096 |
| Post-S2 capture | ✓ | ✗ EIO | ✓ |

**Primary divergence: ALSA access mode and buffer geometry**, not a missing codec or broken DMA after S2.

MMAP + PW period/buffer succeeds on direct ALSA after stopping PipeWire. Default RW `arecord` fails with EIO on the **same** post-S2 kernel state.

---

## Implications

### KPI-U vs KPI-K

- **KPI-U PASS** — expected with PW (uses MMAP + UCM).
- **KPI-K FAIL** with naive `arecord` (RW default) — **not** “kernel cannot capture post-S2”.
- **KPI-K PASS** with PW-matched MMAP probe on both DMIC and RT721 (this session).

### Investigation

- Deprioritize IRQ/DMA “never started” for DMIC post-S2.
- Upstream angle: why **RW capture** EIO while **MMAP capture** works after S2 (driver `copy` vs `mmap` path? DMIC PDM DMA mapping?).
- SmartAmp PIN4 and RT721 paths still need separate probes (`--device hw:1,1`).

### Witness scripts

Update `post-s2-kernel-witness.sh` DMIC probe to use `-M --period-size=1024 --buffer-size=4096` for fair KPI-K.

---

## Next

1. Re-run diff for **RT721** (`--device hw:1,1 --pcm /proc/asound/card1/pcm1c/sub0`) — same MMAP hypothesis?
2. Cold boot vs post-S2: does default RW always fail or only post-S2?
3. Optional: `strace -e ioctl arecord` RW vs MMAP on failing vs passing open.
