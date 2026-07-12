# Phase A — topology PASS, functional playback FAIL (2026-07-12)

English (canonical). Witness: `validation/post-s2-witness/phase-a-20260712-134808`

---

## Summary

Post-S2 Phase A (px13 disabled, untouched) showed **full ALSA + PipeWire topology** but **`speaker-test -D hw:1,2` failed with EIO (-5)** after stream start.

**Topology PASS ≠ fix complete.**

---

## Topology (witness KPI — all OK)

| Check | Result |
|-------|--------|
| px13 | disabled |
| ALSA playback | card1 dev0, dev2 (SmartAmp) |
| ALSA capture | dev1 RT721, dev3 SmartAmp cap, dev4 DMIC |
| PipeWire | Speaker, Headphones, Headset Microphone |
| Dummy Output | absent |

SmartAmp playback showed `Subdevices: 0/1` in `aplay -l` — hint PCM not fully healthy.

---

## Functional (manual, post-witness)

**Playback:**

```text
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1
  → hw_params OK, stream started
  → L: EPIPE (-32), R: EIO (-5)
```

**Capture:**

```text
arecord -D hw:1,1 -f S16_LE -r 48000 -c 2 -d 3 /tmp/post-s2-cap.wav
  → stream opened
  → pcm_read: EIO
```

Both paths fail at **runtime I/O**, not at open/hw_params.

---

## witness-stream-hang (13:51:41 — invalid timing)

Run **after** `arecord` had already exited:

| Signal | Value | Meaning |
|--------|-------|---------|
| `pid=none` | — | no live speaker-test/aplay |
| PCM2 status | `closed` | too late for pointer series |
| IRQ 160 @ +2s | 34 → 34, `d_irq=0` | idle window only |

**Concurrent protocol (required):**

```text
Terminal 1: speaker-test -D hw:1,2 …   # leave blocked OR re-run
Terminal 2: sudo resolution/scripts/witness-stream-hang.sh
```

Need `state: RUNNING` + IRQ delta during stall.

---

## Kernel at arecord time (13:51:39, journal)

All **prepare/program** paths return 0:

- `slave_port OK` (tas2783 :8, :b)
- `amd_xport OK`, `amd_port OK`
- `sdw_program_params ret=0` stream=subdevice #0-Playback

No `error` / `timeout` lines. Failure is **after** SDW programming — consistent with IRQ/DMA not advancing buffers (Branch B / stream stall class), not EINVAL at hw_params.

ACP_PCI_IRQ total **34** this boot (very low vs stall witness #2 @286 frozen).

---

## Classification (revised)

| Layer | Status |
|-------|--------|
| Enumeration / PW nodes | PASS |
| SDW prepare / program | PASS (journal) |
| Playback hw:1,2 | FAIL (EIO) |
| Capture hw:1,1 | FAIL (EIO) |
| IRQ witness this run | **inconclusive** (idle) |

**Not userspace.** Kernel enumerates and programs SDW; **runtime data path broken** on play + capture.

---

## Next

1. Re-run **concurrent** witness during blocked `speaker-test` or `arecord`
2. `sudo dmesg | tail -40` (user dmesg failed without caps)
3. Compare IRQ 160 + `hw_ptr` series vs [w2b-hwptr-stall-witness-20260712b.md](w2b-hwptr-stall-witness-20260712b.md)
4. Branch B (ACP IRQ / handler) back on critical path — W1+W2 fixed attach, not DMA sustain

---

## EBUSY (-16) on retry

After Phase A, **PipeWire holds card1** → direct `hw:1,2` returns **device busy** before open.

```bash
fuser -v /dev/snd/pcmC1D2p /dev/snd/controlC1
```

**Direct ALSA test (kernel path):**

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1
# terminal 2 while blocked:
sudo resolution/scripts/witness-stream-hang.sh
systemctl --user start pipewire wireplumber
```

**Desktop path (no stop):** `pw-play` on default Speaker sink — tests what GNOME uses.
