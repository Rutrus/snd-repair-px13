# Capture access × geometry matrix — post-S2

**2026-07-12 15:04** · script: `scripts/post-s2-capture-access-matrix.sh`

---

## Question

Does post-S2 capture failure depend on **MMAP vs RW**, **buffer geometry**, or **both**?

We changed two variables in the first PW diff; this matrix isolates them.

---

## Method

PipeWire stopped. Four `arecord` probes per device, 2 s each:

| id | Access | Geometry |
|----|--------|------------|
| rw-large | RW (default) | default (~2048 / ~16384) |
| rw-small | RW | `--period-size=1024 --buffer-size=4096` |
| mmap-large | `-M` | default |
| mmap-small | `-M` | 1024 / 4096 |

PASS = exit 0 and WAV **> 1000 bytes** (not header-only).

---

## Results — DMIC `hw:1,4` S32_LE

Artifacts: `validation/capture-access-matrix-20260712-150440/`

| Access | Geometry | Verdict | Bytes |
|--------|----------|---------|-------|
| RW | default | **FAIL** EIO | 44 |
| RW | 1024/4096 | **FAIL** EIO | 44 |
| MMAP | default | **PASS** | 768044 |
| MMAP | 1024/4096 | **PASS** | 768044 |

---

## Results — RT721 `hw:1,1` S16_LE

Artifacts: `validation/capture-access-matrix-rt721-20260712-150500/`

| Access | Geometry | Verdict | Bytes |
|--------|----------|---------|-------|
| RW | default | **FAIL** EIO | 44 |
| RW | 1024/4096 | **FAIL** EIO | 44 |
| MMAP | default | **PASS** | 384044 |
| MMAP | 1024/4096 | **PASS** | 384044 |

---

## Conclusion

**ACCESS mode is the sole determinant** in this session (post-S2):

```text
SNDRV_PCM_ACCESS_MMAP_INTERLEAVED  →  PASS (both geometries)
SNDRV_PCM_ACCESS_RW_INTERLEAVED    →  FAIL (both geometries)
```

Buffer period/buffer size **does not** rescue RW.

Same pattern on **DMIC** and **RT721** — not device-specific.

---

## What is ruled out

- DMA never started post-S2 (MMAP moves data)
- IRQ globally dead post-S2
- SoundWire capture not recovered (RT721 MMAP OK)
- Buffer geometry as root cause

---

## Upstream focus (KPI-K)

If investigating kernel fix:

```text
snd_pcm_readi() / snd_pcm_lib_read() / copy path
```

vs

```text
snd_pcm_mmap_begin() / mmap path
```

Post-S2 regression is in the **RW copy path** for capture PCMs on this machine.

PipeWire uses MMAP → KPI-U PASS. Naive `arecord` uses RW → false “capture broken” signal.

---

## Next steps (priority)

1. ~~Access × geometry matrix~~ **Done**
2. **S2×3** with `post-s2-user-witness.sh` — close KPI-U formally
3. Optional upstream: trace `copy` vs `mmap` in DMIC / SDW capture drivers after resume
4. SmartAmp PIN4 — parked (structural, not user path)
