# KPI-U vs KPI-K — two audio contracts after S2

**2026-07-12** · PX13 post-S2 investigation pivot

---

## Discovery

We were mixing two **non-equivalent** success criteria:

| Contract | Question | Typical probe |
|----------|----------|---------------|
| **KPI-U (User)** | Can a normal user record/play after suspend? | PipeWire, GNOME, apps |
| **KPI-K (Kernel)** | Can direct ALSA open `hw:X,Y` after suspend? | `arecord`, `speaker-test` |

They are related but **not the same**. A KPI-K FAIL does not imply KPI-U FAIL.

---

## Evidence (2026-07-12, post-S2, PipeWire untouched)

| Probe | Result | Notes |
|-------|--------|-------|
| GNOME Sound → Internal Microphone | **Meter moves** with external audio | User witness |
| `wpctl` default source | Internal Microphone → `api.alsa.path = hw:amdsoundwire,4` | DMIC, not RT721 |
| `/proc/asound/card1/pcm4c/sub0/status` | `state: RUNNING`, **hw_ptr advancing** | DMA active |
| `pw-record` Internal Mic (3 s) | **569 KB** valid WAV | Functional |
| `pw-record` Headset Mic (3 s) | **573 KB** valid WAV | Functional |
| `arecord -D hw:1,4` (PW running) | **EBUSY** | PW holds PCM |
| `arecord -D hw:1,4` (PW stopped) | **EIO** on read | KPI-K fail |
| `arecord -D hw:1,1` (PW stopped) | **EIO** on read | KPI-K fail |

**Conclusion:** After S2, capture **works on the user path** (PipeWire + UCM). Direct ALSA fails when PipeWire is stopped and a fresh `hw:` open is attempted.

This is **not** “DMA never started post-S2” — `hw_ptr` moves under PipeWire.

---

## KPI-U (User) — laptop functional?

**Rule:** Phase A only. After `systemctl suspend` → resume, wait 30–45 s. **Do not restart PipeWire.**

### Must pass

```text
Suspend → Resume → wait → PipeWire untouched
  → pw-record @DEFAULT_AUDIO_SOURCE@  → valid WAV + non-silent audio
  → playback (pw-play / app)         → audible
  → Internal / Headset selectable    → both record if present
  → GNOME level meter              → reacts to input
```

Optional: Firefox/Chromium getUserMedia in a videocall.

### Scripts

```bash
./scripts/post-s2-user-witness.sh
```

Output: `validation/post-s2-user-witness/<timestamp>/` with `kpi-u.txt` → `PASS` or `FAIL`.

---

## KPI-K (Kernel) — upstream / ALSA direct?

**Rule:** Stop PipeWire first (exclusive `hw:` access). For SDWCAP, kernel module must be instrumented separately.

### Probes

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
speaker-test -D hw:1,2 ...
arecord -D hw:1,1 ...   # RT721
arecord -D hw:1,4 ...   # DMIC
# hw:1,3 SmartAmp PIN4 — structural, not user mic path
```

### Scripts

```bash
./scripts/post-s2-kernel-witness.sh
```

Output: `validation/post-s2-kernel-witness/<timestamp>/` with per-device PASS/FAIL and optional SDWCAP excerpt.

**KPI-K is for upstream.** Do not use it to declare the laptop broken for users.

---

## Branch status (frozen / active)

| Branch | Status | KPI |
|--------|--------|-----|
| Playback W1+W2 | **Closed** | U + K (playback direct may EBUSY under PW) |
| SmartAmp PIN4 capture | **Documented, parked** | K only; never CONFIGURED at boot; not user mic |
| User capture post-S2 | **Re-evaluate with KPI-U** | U |
| Direct ALSA capture post-S2 | **Open** | K |

---

## Why `arecord` fails but PipeWire works — hypotheses

Ordered by plausibility for next experiment:

1. **Stream configuration diff** — rate/format/period/buffer/channels differ between PW (UCM policy) and bare `arecord -D hw:1,4`.
2. **Extra userspace sequence** — UCM verb, mixer controls, or PW graph setup before trigger.
3. **ACP re-init** — something in PW/UCM path re-enables capture hardware that a naked `open()` does not.

Reference: [../experiments/pw-vs-alsa-diff-20260712.md](../experiments/pw-vs-alsa-diff-20260712.md)

---

## Legacy witness

`scripts/post-s2-card-witness.sh --functional` used **KPI-K-style** probes (`arecord hw:1,1`) while claiming user functional status. That produced **false FAIL** for capture when GNOME/PW were working.

Use:

- `post-s2-user-witness.sh` for laptop KPI
- `post-s2-kernel-witness.sh` for kernel KPI
- `post-s2-card-witness.sh` for topology only (no `--functional` for capture verdict)

---

## Related

- [phase-a-topology-vs-functional-20260712.md](phase-a-topology-vs-functional-20260712.md)
- [sdwcap-lifecycle-post-s2-20260712.md](sdwcap-lifecycle-post-s2-20260712.md)
- [ucm-dmic-install-pass-20260712.md](ucm-dmic-install-pass-20260712.md)
- [../capture-sdw/README.md](../capture-sdw/README.md)
