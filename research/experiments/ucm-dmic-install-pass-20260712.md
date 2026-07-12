# UCM internal DMIC install — PASS (2026-07-12)

English (canonical). Clean boot after `install-ucm-px13.sh`.

Inspection (pre-override): [ucm-dmic-inspection-20260712.md](ucm-dmic-inspection-20260712.md)

---

## Install

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

Files: [`ucm2/sof-soundwire/acp-dmic.conf`](../../ucm2/sof-soundwire/acp-dmic.conf), machine conf append `Define.MicCodec1 "acp-dmic"`.

---

## KPI chain — PASS (boot, untouched)

| Step | Result |
|------|--------|
| ALSA `hw:1,4` | Works (`S32_LE`) |
| UCM `Device.Mic` | Present after HiFi verb |
| PipeWire source | **Internal Microphone** |
| Default input `*` | Internal Mic (not webcam) |
| Headset Mic | Present, not default |
| Speaker sink | Default `*` |

### wpctl (user witness)

```text
Sinks:
  * 59. Audio Coprocessor Speaker
Sources:
  * 61. Audio Coprocessor Internal Microphone
    62. Audio Coprocessor Headset Microphone
```

### pw-cli

```text
node.description = "Audio Coprocessor Internal Microphone"
node.nick = "Internal Microphone"
node.description = "Audio Coprocessor Headset Microphone"
node.nick = "Headset Microphone"
```

User confirmed: **functional** (audible / recording OK in desktop apps).

---

## Scope

| Fixed by this change | Not fixed |
|----------------------|-----------|
| GNOME / PW input discovery on **clean boot** | Post-S2 stream EIO (kernel) |
| Default internal mic vs webcam | `px13-audio-resume` vs W1+W2 conflict |
| UCM Case B (no Mic device) | Persistence S2×3/×10 |

---

## Post-suspend expectations

See [post-s2-expectations-after-ucm-dmic.md](post-s2-expectations-after-ucm-dmic.md).

Quick protocol after S2:

```bash
sleep 45
./scripts/post-s2-card-witness.sh --phase-a --functional
```

Do **not** assume mic/speaker work because nodes appear in `wpctl`.

---

## References

- Install: [`ucm2/README.md`](../../ucm2/README.md)
- Post-S2 functional fail (same day): [phase-a-topology-vs-functional-20260712.md](phase-a-topology-vs-functional-20260712.md)
- Full-card KPI: [w2-full-card-recovery-kpi.md](w2-full-card-recovery-kpi.md)
