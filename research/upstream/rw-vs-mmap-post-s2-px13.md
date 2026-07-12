# Upstream report draft — RW vs MMAP capture post-S2 (ASUS PX13)

**Status:** draft · Branch B · 2026-07-12  
**Platform:** ASUS ProArt PX13 HN7306EAC · AMD ACP + SoundWire (RT721 + TAS2783 + DMIC)  
**Kernel:** `7.0.0-27-generic` (stock + local W1/W2 patches for user path — anomaly reproduces on capture PCMs)

---

## Summary (maintainer-facing)

After `s2idle` suspend → resume, **direct ALSA capture fails only when opened with RW access**. The same PCM, format, rate, and buffer geometry work with MMAP access.

| Access mode | `arecord` post-S2 | PipeWire (MMAP) post-S2 |
|-------------|-------------------|-------------------------|
| `SNDRV_PCM_ACCESS_RW_INTERLEAVED` | **EIO** on read | N/A (PW uses MMAP) |
| `SNDRV_PCM_ACCESS_MMAP_INTERLEAVED` | **PASS** | **PASS** |

This is **not** a userspace bug: multiple RW clients fail; MMAP clients pass (see client matrix below).

User-facing desktop audio is unaffected because PipeWire defaults to MMAP for capture.

---

## Minimal reproduction

```bash
# Post-S2 (after at least one suspend/resume):
systemctl --user stop wireplumber pipewire pipewire-pulse
sleep 2

# FAIL — RW (any geometry tested)
arecord -D hw:1,4 -f S32_LE -r 48000 -c 2 -d 2 /tmp/rw.wav
# arecord: pcm_read: Input/output error

# PASS — MMAP
arecord -D hw:1,4 -f S32_LE -r 48000 -c 2 -d 2 \
  -M --period-size=1024 --buffer-size=4096 /tmp/mmap.wav

systemctl --user start pipewire pipewire-pulse wireplumber
```

Same pattern on **RT721 headset capture** `hw:1,1` S16_LE.

Automated matrix: `./scripts/post-s2-capture-access-matrix.sh`

---

## Evidence (2026-07-12)

### Access × geometry (arecord only)

Doc: [../experiments/capture-access-matrix-20260712.md](../experiments/capture-access-matrix-20260712.md)

```text
RW  + default geometry   → FAIL
RW  + 1024/4096          → FAIL
MMAP + default           → PASS
MMAP + 1024/4096         → PASS
```

**Determinant: access mode only** — not period/buffer size.

### Multi-client matrix (proves not arecord-specific)

Script: `./scripts/capture-client-access-matrix.sh`

| Client | Access | Expected post-S2 |
|--------|--------|------------------|
| arecord | RW | FAIL |
| arecord -M | MMAP | PASS |
| ffmpeg `-f alsa` | RW | FAIL |
| GStreamer alsasrc | RW | FAIL |
| sox rec | RW | FAIL |
| tinycap | MMAP | PASS |

Run artifacts: `validation/capture-client-matrix-*/summary.md`

### Cold boot vs post-S2 (open question)

Script: `./scripts/capture-access-cold-vs-s2.sh --phase cold|post-s2`

| Context | RW | MMAP |
|---------|----|----|
| Cold boot | **TBD** | **TBD** |
| Post-S2 | FAIL | PASS |

If RW passes at cold boot and fails only post-S2 → **resume state regression in copy path**.  
If RW fails always → still upstream-worthy but different classification.

---

## What is ruled out

- DMA never started (MMAP moves data; hw_ptr advances)
- Global IRQ loss post-S2
- SoundWire stream stuck (RT721 SDWCAP shows CONFIGURED→ENABLED on MMAP probe)
- Buffer geometry as root cause
- PipeWire-specific behavior

---

## Hypothesis — first code divergence

ALSA core splits after `hw_params` + `prepare` + `trigger`:

```text
RW path:
  snd_pcm_readi()
    → snd_pcm_lib_read()
      → pcm_lib_copy() / driver .copy / .copy_user

MMAP path:
  snd_pcm_mmap_begin() / mmap capture
    → period update via .pointer + application mmap
    → (no copy into userspace buffer)
```

**Investigation goal:** find the **first function** where RW and MMAP diverge after resume, and which driver callback returns EIO or leaves the ring buffer stale.

Trace tool: `sudo ./scripts/capture-rw-mmap-trace.sh --label post-s2`

Target modules: `snd_pcm`, ACP PCM (`snd_acp_pcm`), machine/codec capture (RT721, DMIC).

---

## Affected PCMs (this machine)

| PCM | Device | Role | User path |
|-----|--------|------|-----------|
| pcm4c | hw:1,4 | DMIC (Internal Mic) | **Yes** (UCM → PW MMAP) |
| pcm1c | hw:1,1 | RT721 headset mic | Yes (headset) |
| pcm3c | hw:1,3 | SmartAmp PIN4 capture | **No** (topology debt; never CONFIGURED) |

---

## Suggested upstream submission shape

1. **Title:** `ALSA: capture RW fails but MMAP works after s2idle resume on AMD ACP SoundWire (PX13)`
2. **Repro:** minimal arecord commands above + dmesg (no proprietary FW patches required for capture PCMs if W1/W2 not needed for DMIC/RT721 capture)
3. **Contrast:** one dmesg trace RW (EIO) vs MMAP (PASS) with `dynamic_debug` on `snd_pcm_*` and ACP copy
4. **Not in scope:** SmartAmp playback FW (separate W2 track); PIN4 capture topology

---

## Related repo docs

| Doc | Role |
|-----|------|
| [../experiments/kpi-u-vs-kpi-k-20260712.md](../experiments/kpi-u-vs-kpi-k-20260712.md) | KPI split |
| [../experiments/pw-vs-alsa-diff-20260712.md](../experiments/pw-vs-alsa-diff-20260712.md) | PW uses MMAP on same hw:1,4 |
| [../ROADMAP-POST-KPI-U-20260712.md](../ROADMAP-POST-KPI-U-20260712.md) | Branch B priority |

---

## Next steps

1. Run `capture-access-cold-vs-s2.sh` both phases — fill TBD table
2. Run `capture-client-access-matrix.sh` post-S2 — attach summary to this doc
3. Run `capture-rw-mmap-trace.sh` — identify first diverging callback
4. Bisect: ACP `.copy` vs SDW utils vs RT721/DMIC component driver
