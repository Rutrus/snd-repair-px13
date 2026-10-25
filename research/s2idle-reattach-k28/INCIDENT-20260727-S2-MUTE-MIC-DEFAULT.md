# Incident — post-S2 mute + “no mic” (2026-07-27)

**Host:** colosal3 · PX13 HN7306EAC · `7.0.0-28-generic`  
**Wake:** ~18:57 local · overlay `installed_at=2026-07-23T13:35:52` (0001/0001b/0002/0003/0003b)  
**User symptom:** no sound after S2; no recording / “no input device”  
**Language:** English (canonical research note)

---

## Verdict

Two independent failures stacked after one S2:

1. **Playback mute (Scenario 2):** Case B + 0001b OK; open PipeWire path stayed silent until sink flip / PCM reopen.
2. **Mic “missing” (WirePlumber default):** hardware sources present; default `Audio/Source` pointed at **Speaker sink** (monitor), often rewritten with EShareAudio preferences.

Neither required reboot or PCI reset.

---

## Evidence

### Kernel — Case B closed

| Check | Result |
|-------|--------|
| Slaves after wake | **Attached** ×3 (`:8`, `:b`, rt721) |
| Delayed enum kick | `pend=0x4` (0003b) |
| `-110` / UNATTACHED / FW timeout storm | absent |
| 0001b | `snd_repair post-resume fw_reinit` on both TAS |

PCM lifecycle traces on this wake showed `trigger_SUSPEND` → resume kick → `trigger_RESUME` → STOP → **port_prep** → **prepare** → **trigger_START**. Prepare/START ran; silence still matched Scenario 2 (reopen required).

### Userspace — dual stack

| Check | Result |
|-------|--------|
| Default sink | Speaker `*` |
| Streams | Firefox active; PCM `RUNNING` |
| Default source | `…HiFi__Speaker__sink` (**wrong**) |
| `default-nodes` | `default.configured.audio.source=…Speaker__sink` |
| Real sources | Digital Microphone + Headset Microphone present |
| Extra sink | EShareAudio in sink preference list |

---

## Causal chain

```text
S2 → 0003b delayed kick → Attached ×3          (Case B PASS)
   → 0001b fw_reinit                             (marker OK)
   → PipeWire keeps / recovers open playback     (Scenario 2 mute)
   → WirePlumber (EShare churn) sets
       Audio/Source = Speaker sink               (“no mic” UX)
```

---

## Recovery applied (no reboot) — 2026-07-27 ~19:51

1. `wpctl set-default` → Digital Microphone (id 68); unmute; volume 1.0.
2. Rewrite `~/.local/state/wireplumber/default-nodes` so source = `…HiFi__Mic__source` (scrub Speaker-as-source).
3. Sink flip Headphones → Speaker to force PCM reopen.
4. Smoke: `speaker-test -D pipewire`; `pw-record` → `/tmp/mic-post-s2.wav` (~2 s PCM 48 kHz).

Post-fix: Speaker `*`, Digital Microphone `*`, configured `Audio/Source` = Mic.

### Follow-up same evening (~19:54)

User: still no speaker-test; digital mic OK; **jack input dead**.

| Check | Result |
|-------|--------|
| Headphone Jack / Headset Mic Jack | both **`off`** (kernel) |
| PW ports Headphones / Headset | **not available** |
| After PW restart | full `hw_params`→`prepare`→`START`; **no** second `post-resume fw_reinit` (0001b already claimed at wake) |
| Forcing `Headphone on` with jack=`off` | steals route from speakers — avoid |

Conclusion: mute escalated past sink-flip (need TAS slave rebind / next sleep to re-arm 0001b). Jack mic blocked by **detect=`off`** (unplugged or stuck RT721 jack) — cycle `rt721-sdca` or unplug/replug.

Script: `scripts/recover-post-s2-mute-no-reboot.sh` (sudo, SDW only — not PCI).

---

## Product implications

| Do | Do not |
|----|--------|
| Document dual check (SDW + WP defaults) in troubleshooting | Treat “no mic” as UCM-missing when Sources list is non-empty |
| Recover with sink flip / PW restart + `wpctl set-default` | More delayed `fw_reinit` (0001c) for Scenario 2 |
| Watch EShare / virtual sinks rewriting defaults | Live PCI unbind/bind |

See also: [CASE-A-PRIME-PCM-LIFECYCLE-20260723.md](CASE-A-PRIME-PCM-LIFECYCLE-20260723.md), [docs/troubleshooting.md](../../docs/troubleshooting.md) (“Post-S2: silent speakers + no mic”).
