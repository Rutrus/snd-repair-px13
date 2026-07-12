# W3 Experiment A — result (2026-07-12)

Build: W3 diagnostic module (B + W2 + W3), `w3_dapm_sync_probe=0`.

## Outcome

| Field | Value |
|-------|-------|
| **heard_tone post-S2** | **no** (user confirmed) |
| Cold boot audible | yes (implicit — S2 attempted) |
| PipeWire sink | Audio Coprocessor Speaker (not Dummy) |
| pass-cold snapshot | `validation/playback-snapshot-pass-cold-20260712-173934` |
| fail-silent snapshot | `validation/playback-snapshot-fail-silent-20260712-174932` |
| suspend_count | 1 |

---

## Demonstrated (this run)

1. **Silent playback after S2** reproduces with W3 instrumentation — W3 is diagnostic only, not a fix.
2. **W2 ladder OK:** at 17:48:55 both codecs `:8` and `:b` → `force_fw_reinit` → `fw_reinit ret=0 hw_init=1 fw_ok=1`.
3. **POST_PMU fires on first playback after S2** (17:49:24):

   ```
   fu21_event event=2 → FU_MUTE=0  (:8, :b)
   fu23_event event=2 → FU_MUTE=0
   ```

4. **Mixers sane:** Left/Right Spk ON, tas2783 amp/speaker at max.

## Hypothesis impact

| Hypothesis | Result |
|------------|--------|
| FU21/FU23 POST_PMU not re-run after fw_reinit | **Weakened** — events fire, FU_MUTE=0 written |
| ASoC DAPM widget state desync (broader than FU_MUTE) | **Still open** — Exp B (`dapm_sync`) tests this |
| FW download OK but DSP/analog path dead | **Still open** — success=1 ≠ audible |

No `W3 ctx=dapm tag=post-fw_reinit widget=…` lines in dmesg (widget logger may not match card widgets at fw_reinit time — follow-up).

---

## Preconditions (done)

| Check | Status |
|-------|--------|
| `w3_dapm_sync_probe=0` | OK |
| `px13-audio-resume.service` | disabled |
| Cold boot `suspend_count=0` | OK |

---

## Next — Experiment B (same boot or after reboot)

**Requires** `w3_dapm_sync_probe=1` **before** suspend (module param read at fw_reinit time).

```bash
# Reboot if you already suspended this boot and want a clean B run:
# sudo reboot

echo 1 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe
cat /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe   # expect Y

systemctl suspend
# wake:
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
journalctl -k -b 0 --since '10 min ago' | grep 'W3 ctx='
```

| Hear tone? | Action |
|------------|--------|
| **Yes** | Design targeted fix: `snd_soc_dapm_sync` after fw_reinit |
| **No** | Deprioritize DAPM-only; next: PDE23, SDCA readback, DSP state |

Reset after B: `echo 0 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe`

---

## References

- Protocol: [w3-dapm-diagnostic-protocol.md](w3-dapm-diagnostic-protocol.md)
- Symptom doc: [silent-playback-dapm-fu-mute-20260712.md](silent-playback-dapm-fu-mute-20260712.md)
