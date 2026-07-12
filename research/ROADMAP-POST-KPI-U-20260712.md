# Project roadmap — post KPI-U closure (2026-07-12)

English (canonical).

---

## Branch A — FROZEN ✓

**User laptop audio after S2 is resolved.**

Stack: W1 (IRQ/ATTACH) + W2 (TAS2783 FW) + UCM (`install-ucm-px13.sh`) + PipeWire (MMAP).

Evidence:

- KPI-U S2×3 PASS — runs `150956`, `152551`
- Matrix: MMAP capture OK; RW fails (KPI-K only)

Doc: [SOLUTION-CLOSURE-KPI-U-20260712.md](SOLUTION-CLOSURE-KPI-U-20260712.md)

Verify anytime:

```bash
./scripts/post-s2-persistence-run.sh 3
./scripts/post-s2-user-witness.sh
```

---

## Branch B — RW vs MMAP (upstream, active)

**Question:** What differs in the driver between `SNDRV_PCM_ACCESS_RW_INTERLEAVED` and `SNDRV_PCM_ACCESS_MMAP_INTERLEAVED` after resume?

**Not:** generic DMA/IRQ/SoundWire hunting.

Evidence: [experiments/capture-access-matrix-20260712.md](experiments/capture-access-matrix-20260712.md)

Tools:

```bash
./scripts/post-s2-capture-access-matrix.sh
./scripts/post-s2-kernel-witness.sh   # kpi_k_rw vs kpi_k_mmap
./scripts/post-s2-pw-vs-alsa-diff.sh
```

Target: driver `.copy` / `snd_pcm_readi` path (DMIC + RT721).

---

## Branch C — Extended validation (optional confidence)

Not blocking closure. Manual or scripted:

| Test | Why |
|------|-----|
| Full duplex | `pw-play` + `pw-record` simultaneous post-S2 |
| Jack hotplug | plug/unplug/re-plug after resume |
| Rate sweep | 44.1 / 48 / 96 kHz |
| Stress loop | play+record each cycle, 100× S2 |

---

## Branch D — PARKED

**SmartAmp PIN4 capture** — structural (no source_ports), not user path. Track B / upstream cleanup only.

---

## Priority order

1. ~~KPI-U closure~~ **Done**
2. Fix witness scripts (kernel witness rc capture) **Done**
3. RW vs MMAP upstream report + driver trace
4. Extended validation (duplex, hotplug, stress)
5. PIN4 machine topology (low)
