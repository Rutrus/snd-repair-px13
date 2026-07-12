# Post-suspend expectations — after UCM DMIC fix (2026-07-12)

English (canonical). What should and should **not** be assumed after `systemctl suspend` → resume.

Boot mic fix: [ucm-dmic-install-pass-20260712.md](ucm-dmic-install-pass-20260712.md)

---

## Two independent layers

```text
Layer 1 — Userspace (UCM / PipeWire / GNOME)
  Clean boot: Internal Mic + Speaker visible, default routes OK  ✓ (2026-07-12)

Layer 2 — Kernel streams (W1+W2, ACP IRQ / SDW DMA)
  Post-S2: topology may OK, functional play/capture may FAIL  ✗ (witness same day)
```

UCM override does **not** change kernel resume behavior.

---

## Expected after S2 (px13 disabled, W1+W2 loaded)

Run **Phase A only** — wait **45 s**, do not restart WirePlumber first.

### Likely (based on 2026-07-12 witness)

| Check | Expected | Notes |
|-------|----------|-------|
| `px13-audio-resume` | disabled | Required for clean test |
| ALSA PCMs in `/proc/asound/pcm` | **Probably visible** | play + capture nodes listed |
| `wpctl` Speaker + Internal Mic | **Probably visible** | Topology can look healthy |
| `speaker-test -D hw:1,2` (PW stopped) | **May FAIL** | EIO mid-stream class |
| `arecord hw:1,1` / `hw:1,4` | **May FAIL** | EIO on read |
| Audible speaker / working mic in apps | **Not guaranteed** | **Functional KPI** |

**Rule:** Topology PASS ≠ functional PASS. Always use `--functional` or manual `speaker-test` / `arecord` / `pw-record`.

### If functional FAIL (observed pattern)

```text
Open/hw_params OK  →  SDW program OK (journal)  →  EIO during I/O
```

Both playback and capture fail → **shared kernel data path**, not UCM-only.

Next: concurrent `witness-stream-hang.sh` during blocked stream; IRQ 160 / `hw_ptr` series.

### If functional PASS

Run persistence:

```bash
./scripts/post-s2-persistence-run.sh 3
```

Then ×10 before calling Branch A closed.

---

## PipeWire-specific notes

| Topic | Expectation |
|-------|-------------|
| Internal Mic node after S2 | May still **appear** in `wpctl` (stale or re-probed) |
| Default route | May revert to webcam or wrong source — check `*` in `wpctl status` |
| Phase B (WP restart) | Only if Phase A shows **PW incomplete** (category 2), not if ALSA direct fails |
| EBUSY on `hw:1,2` | PipeWire holds PCM — stop PW for direct ALSA test |

---

## Decision tree (one line after S2)

```text
Phase A --functional
  ├─ play ✓ cap ✓ PW ✓  →  persistence ×3/×10
  ├─ play ✓ cap ✓ PW ✗  →  Phase B (WP restart), separate run
  ├─ play ✗ or cap ✗     →  kernel (W1/W2 / IRQ), UCM irrelevant
  └─ nodes OK, I/O ✗     →  kernel stream stall (current hypothesis)
```

---

## Preconditions (unchanged)

```bash
sudo ./scripts/build-w1-w2.sh && sudo reboot   # if modules updated
sudo systemctl disable --now px13-audio-resume.service
sudo ./scripts/install-ucm-px13.sh             # once; survives reboot
```

---

## References

- Witness: [`scripts/post-s2-card-witness.sh`](../../scripts/post-s2-card-witness.sh)
- Functional fail log: [phase-a-topology-vs-functional-20260712.md](phase-a-topology-vs-functional-20260712.md)
- Queue: [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md)
