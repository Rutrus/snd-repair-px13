# Full card recovery KPI — post-S2 (W1+W2)

English (canonical). **2026-07-12** pivot after Case C playback PASS.

Prior playback-only KPI: [w2b-prime-case-c-20260712.md](w2b-prime-case-c-20260712.md)

---

## KPI shift

We no longer chase a symptom (`-EINVAL`). We validate **expected full-system behavior after resume**.

| Phase | Question |
|-------|----------|
| **Before** | Does playback work? (`speaker-test -D hw:1,2`) |
| **Now** | Does the **full card** recover? **playback + capture + UCM + PipeWire (+ GNOME)** |

`speaker-test` proves playback path is **largely fixed** (Case C). **Not sufficient** for “fix complete” if capture or PW fail.

---

## Methodology — three rules

### 1. Never mix Phase A and Phase B in one witness

| Phase | When | Meaning |
|-------|------|---------|
| **A** | Post-resume, **nothing touched** | What kernel + boot-time PW state deliver |
| **B** | **After** explicit userspace recovery | What `wireplumber` restart fixes |

```text
Phase A:  resume → wait 45 s → post-s2-card-witness.sh --phase-a
Phase B:  systemctl --user restart wireplumber pipewire → post-s2-card-witness.sh --phase-b
```

Separate output dirs: `validation/post-s2-witness/phase-a-*` vs `phase-b-*`.

### 2. Persistence KPI (PM bugs often appear on cycle 2+)

| Gate | Target |
|------|--------|
| S2 ×1 | Phase A topology + **`--functional`** (hw:1,2 audible) |
| S2 ×3 | Same every cycle |
| S2 ×10 | Robust — kernel fix candidate |

**Topology alone is not PASS.** Nodes in ALSA/PW without audible SmartAmp playback = functional FAIL (EIO stall class).

```bash
./scripts/post-s2-persistence-run.sh 3
# summary → validation/post-s2-persistence-summary.csv
```

Phase A only during persistence — **no** WirePlumber restart between cycles.

### 3. Full topology in witness

Automated in [post-s2-card-witness.sh](../../scripts/post-s2-card-witness.sh):

- ALSA: `aplay -l`, `arecord -l`, `/proc/asound/pcm`
- UCM: `alsaucm` dump
- PipeWire: `wpctl`, `pactl list short sinks/sources`, `pw-cli`, **`pw-dump.json`**

---

## Two hardware paths

| Path | Hardware | ALSA |
|------|----------|------|
| Playback | TAS2783 SmartAmp | `hw:1,2` |
| Capture | RT721, TAS cap, DMIC | `hw:1,1`, `hw:1,3`, `hw:1,4` |

Do not assume one bug for both.

---

## Single next experiment (recommended)

```text
Clean boot (W1+W2, px13 disabled)
  → systemctl suspend
  → resume
  → wait 45 s
  → ./scripts/post-s2-card-witness.sh --phase-a
  → do NOT touch anything else
```

| Phase A result | Next step |
|----------------|-----------|
| Play ✓ Capture ✓ PW ✓ | **Done** (kernel + session OK) |
| Play ✓ Capture ✓ PW ✗ | **W2d** — desktop integration only |
| Play ✓ Capture ✗ | **Kernel** — RT721 / capture DAIs |
| Play ✗ | Kernel — TAS2783 / W2 path |

Only if Phase A shows PW ✗, run Phase B in a **separate** session/cycle:

```bash
systemctl --user restart wireplumber pipewire
./scripts/post-s2-card-witness.sh --phase-b
```

**W2d automation on hold** until Phase A proves category 2.

---

## Classification matrix

| # | ALSA play | ALSA cap | PipeWire | GNOME | Action |
|---|-----------|----------|----------|-------|--------|
| 1 | OK | KO | — | — | Kernel — RT721 |
| 2 | OK | OK | KO | — | W2d (Phase B proves fix) |
| 3 | OK | OK | OK | wrong | WP policy / GNOME |
| 4 | OK | OK | OK | OK | Full PASS |

---

## Confounds

| Item | Action |
|------|--------|
| `px13-audio-resume` | **disable** |
| px13 PCI reset | destroys W2 state |
| PW restart before Phase A | invalidates Phase A |

---

## Stack

```bash
sudo ./scripts/build-w1-w2.sh && sudo reboot
sudo systemctl disable --now px13-audio-resume.service
```

**Priority:** systematic validation over new kernel patches until persistence + Phase A classify.

---

## References

- [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md)
- [../tracks/TRACK-D-PIPEWIRE-PM.md](../tracks/TRACK-D-PIPEWIRE-PM.md)
- [../phase-6/RT721-INSTRUMENTATION.md](../phase-6/RT721-INSTRUMENTATION.md)
