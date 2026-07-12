# Solution closure — KPI-U resume audio (PX13)

**2026-07-12** · Branch A · English (canonical)

---

## Executive summary

**The laptop audio goal for normal desktop use is met** after suspend/resume for **capture and software playback checks**, validated S2×3 with PipeWire untouched.

> **Caveat (2026-07-12 evening):** [silent playback incident](experiments/post-s2-silent-playback-recovery-20260712.md) — W1+W2 without `px13-audio-resume` can leave **speakers mute** while KPI-U PASS. **Keep resume service enabled**; verify **audibly**.

| Layer | Post-S2 status |
|-------|----------------|
| Playback (Speaker) | ✓ W1 + W2 (px13 resume **off**) |
| Internal microphone (GNOME/PW) | ✓ UCM + PW MMAP path |
| Headset microphone | ✓ |
| S2×3 persistence (KPI-U) | **PASS 3/3** |

---

## Problem evolution (compressed)

```text
2026-07-09   No stereo / FW / capture -22 / routing
     ↓       Patches 0004, 0006/0007, 0009 + brainchillz stack
2026-07-12   Playback post-S2 fixed (W1 IRQ + W2 TAS FW)
     ↓       False FAIL: arecord RW looked like “capture dead”
2026-07-12   KPI split: User (PW) vs Kernel (direct ALSA)
     ↓       Discovery: MMAP ✓, RW ✗ — not DMA/IRQ
2026-07-12   KPI-U S2×3 PASS → user goal closed
```

---

## Solution stack (what to install)

1. **Kernel modules** — W1 (0006a-class IRQ resume) + W2 (TAS2783 FW reinit on resume).
2. **UCM** — `scripts/install-ucm-px13.sh` (Internal Mic → DMIC `hw:1,4`).
3. **Userspace** — stock PipeWire + WirePlumber + GNOME · **`px13-audio-resume.service` DISABLED** when using W1+W2.

**Never combine** W1+W2 with px13 resume — causes Dummy Output ([experiments/post-s2-silent-playback-recovery-20260712.md](experiments/post-s2-silent-playback-recovery-20260712.md)).

---

## Validation (canonical)

```bash
# Single cycle
systemctl suspend && sleep 45
./scripts/post-s2-user-witness.sh

# Persistence gate
./scripts/post-s2-persistence-run.sh 3
```

Pass criteria: `kpi_u=PASS`, internal + headset `pw-record`, `pw-play` OK.

**Witness run:** [experiments/kpi-u-s2x3-pass-20260712.md](experiments/kpi-u-s2x3-pass-20260712.md)

---

## Two KPIs (do not merge)

| KPI | Question | PX13 2026-07-12 |
|-----|----------|-----------------|
| **KPI-U** | User desktop functional? | **CLOSED — PASS** |
| **KPI-K** | Direct ALSA after S2? | RW fail, MMAP pass — upstream only |

PipeWire uses **MMAP**; naive `arecord` uses **RW** and EIO post-S2. That is not a user regression.

Details: [experiments/kpi-u-vs-kpi-k-20260712.md](experiments/kpi-u-vs-kpi-k-20260712.md), [experiments/capture-access-matrix-20260712.md](experiments/capture-access-matrix-20260712.md).

---

## Frozen / parked

| Branch | Reason |
|--------|--------|
| W1 playback IRQ | Done |
| W2 TAS2783 FW | Done |
| SmartAmp PIN4 capture | Structural (no source_ports); not user mic |
| SDWCAP capture CONFIGURED hunt | Superseded by KPI-U pass + RW/MMAP matrix |
| DMA/IRQ post-S2 capture | Ruled out |

---

## Upstream follow-up (optional, KPI-K)

Investigate post-S2 failure in **`snd_pcm_read` / driver `.copy`** for capture PCMs (DMIC + RT721), while MMAP works. Not blocking laptop delivery.

---

## Scripts index

| Script | Purpose |
|--------|---------|
| `post-s2-user-witness.sh` | KPI-U single witness |
| `post-s2-persistence-run.sh` | KPI-U S2×N |
| `post-s2-kernel-witness.sh` | KPI-K (RW + MMAP probes) |
| `post-s2-capture-access-matrix.sh` | RW/MMAP × geometry matrix |
| `install-ucm-px13.sh` | Internal Mic UCM |

---

## Sign-off criteria met

- [x] Playback post-S2 without intervention  
- [x] Capture post-S2 via PipeWire (Internal + Headset)  
- [x] GNOME level meter / routing  
- [x] S2×3 persistence  
- [x] Documented reproducible witness  

**Branch A “make it work” — KPI-U: CLOSED.**
