# Witness Quality — audio chain layers

English (canonical). Separates:

1. **Did we reproduce the broken state (S2)?**
2. **Does recovery restore a functional pipeline (S2 → S3)?**

---

## Chain model (authoritative)

```text
Kernel (L1)     card + aplay -l
    ↓
ALSA hw (L2)    speaker-test -D hw:X,Y  ← failure starts here
    ↓           plughw PASS = open only, NOT success
PipeWire (L3)   real sink (not Dummy Output)
    ↓           Dummy = consequence of broken ALSA hw
Default (L4)    default sink ≠ dummy
Audible (L5)    manual listen
```

**Dummy Output is not the cause.** WirePlumber creates it when no usable ALSA sink exists.

**plughw trap:** `plughw` adds software format conversion. PASS means ALSA accepted the open call — not that DAPM/codec/SmartAmp reproduce sound.

---

## Automated verdicts

| Result | Meaning |
|--------|---------|
| **PASS** | L1 + L2 hw + L3 real sink + L4 real default |
| **PARTIAL** | L1 + L2 hw OK, but PipeWire still dummy / no real default |
| **FALSE_PASS** | plughw opens, hw or userspace failed — historical strategies only |
| **FAIL** | L1 or **primary** L2 (`hw:1,2`) broken |

L2 failure class matters: `set_params_fail` = `snd_pcm_hw_params()` rejected config (lower than playback fail).

L5 (audible) is never automated.

**Per-PCM probe:** [../research/pcm-s2-set-params-witness.md](../research/pcm-s2-set-params-witness.md)

---

## S2 certification (W2)

**S2 symptom:** suspend → card present → **ALSA hw playback fail**

Valid even when:

- RT721 sysfs attached
- no journal `-110`
- `plughw` speaker-test PASS
- PipeWire shows Dummy Output only

```bash
sudo resolution/scripts/witness-audio-chain.sh
sudo resolution/scripts/s2-oracle.sh
```

---

## Scripts

| Script | Role |
|--------|------|
| `scripts/witness-pcm-probe.sh` | **Per-PCM** set_params / sysfs / stderr log |
| `scripts/witness-audio-chain.sh` | Layer dump: pcm, hw/plughw, wpctl, amixer |
| `scripts/s2-reproduce.sh` | Suspend loop — maximize W2 hits |
| `scripts/s2-oracle.sh` | Post-suspend witness (no recovery) |
| `scripts/bruteforce/_lib.sh` | `bf_witness_recovery_pass` — strict L1–L4 |

Env:

| Var | Default | Role |
|-----|---------|------|
| `PX13_ALSA_DEV` | `hw:1,2` (auto) | Hardware PCM device |
| `PX13_ALSA_PCM` | `2` | PCM index when card auto-detected |
| `RESOLUTION_MIN_WITNESS` | `W2` | Minimum quality to run recovery |

---

## Investigation focus (post-witness)

When L1 PASS + primary PCM `set_params_fail`:

```bash
sudo resolution/scripts/witness-pcm-probe.sh
```

Captures per-PCM: sysfs `info/status/hw_params`, aplay stderr, error class (`set_params_fail`, `busy`, `einval`, …).

Hypothesis chain:

```text
Suspend → snd_pcm_hw_params() fails on SmartAmp (hw:1,2)
       → ALSA hw broken
       → WirePlumber → Dummy Output (symptom only)
```

PASS requires **primary PCM** + **real sink**, not SimpleJack fallback alone.

---

## Related

- [PCM2-investigation-framing.md](../research/PCM2-investigation-framing.md) — **active framing** (PCM2 only)
- [STATE-GRAPH.md](STATE-GRAPH.md)
- [bruteforce/README.md](bruteforce/README.md)
- `research/phase-8/` — handler_since_pm, STAT1
