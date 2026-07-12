# Capture stream runtime — classification protocol (post-S2)

English (canonical). **2026-07-12** priority pivot after Phase A witness with functional split.

Prior context: [phase-a-topology-vs-functional-20260712.md](phase-a-topology-vs-functional-20260712.md), [ucm-dmic-install-pass-20260712.md](ucm-dmic-install-pass-20260712.md)

---

## Frozen (do not change)

| Layer | Status |
|-------|--------|
| W1 (IRQ resume) | Done — do not extend |
| W2 (TAS2783 FW reinit) | Done — do not extend |
| UCM / PipeWire / GNOME discovery | Done — Internal Mic PASS on boot |

**No further W2 or UCM work** unless capture classification proves userspace regression.

---

## Witness KPI (decisive split)

```text
enumeration        PASS   (alsa_playback/capture_pcm, pw_speaker/source)
playback runtime   PASS   (func_playback_hw12=1)
capture topology   PASS   (nodes visible)
capture runtime    FAIL   (func_capture_hw11=0, EIO)
```

PipeWire is **out of scope** for this failure: if `arecord -D hw:1,1` EIOs, PW cannot fix it.

---

## Triple probe (next experiment)

Run **Phase A post-S2**, untouched, after `sleep 45`:

```bash
./scripts/post-s2-capture-triple-probe.sh
```

Or manual:

```bash
arecord -D hw:1,1 -f S16_LE -r 48000 -c 2 -d 3 /tmp/rt721.wav
arecord -D hw:1,3 -f S16_LE -r 48000 -c 2 -d 3 /tmp/smartamp.wav
arecord -D hw:1,4 -f S32_LE -r 48000 -c 2 -d 3 /tmp/dmic.wav
```

| Device | Path |
|--------|------|
| `hw:1,1` | RT721 jack capture |
| `hw:1,3` | SmartAmp capture |
| `hw:1,4` | ACP DMIC internal |

### Classification

| Case | Fails | Implies |
|------|-------|---------|
| **A** | `hw:1,1` only | RT721 resume / jack capture stream |
| **B** | `1,1` + `1,3` + `1,4` | Shared SoundWire **capture** path |
| **C** | `hw:1,4` only | ACP DMIC isolated |
| **ALL PASS** | none | Capture fixed — run persistence ×3/×10 |

---

## During EIO (same instant)

```bash
cat /proc/asound/card1/pcm1c/sub0/status   # RT721
cat /proc/asound/card1/pcm4c/sub0/status   # DMIC (if open)
# state hw_ptr appl_ptr avail delay
```

Concurrent hang witness (if stream blocks instead of immediate EIO):

```bash
# terminal 1: arecord … -d 30
# terminal 2: sudo resolution/scripts/witness-stream-hang.sh
```

---

## Kernel (post-EIO)

```bash
journalctl -k --since "1 minute ago"
```

Look for (not FW timeout):

- `sdw_deprepare_stream` / `prepare_stream`
- `Program transport params`
- capture-direction SDW / RT721 / dmic errors

---

## Investigation map (current)

```text
1. IRQ resume           → W1 ✓
2. TAS2783 FW           → W2 ✓
3. Enumeration / UCM/PW → ✓
4. Capture stream start → OPEN (single remaining kernel block)
```

Playback runtime PASS + capture runtime FAIL narrows to **capture stream execution**, not card recovery enumeration.

---

## References

- Script: [`scripts/post-s2-capture-triple-probe.sh`](../../scripts/post-s2-capture-triple-probe.sh)
- RT721: [../phase-6/RT721-INSTRUMENTATION.md](../phase-6/RT721-INSTRUMENTATION.md)
- Queue: [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md)
