# W3 — DAPM diagnostic protocol (post silent playback)

English (canonical). **Diagnostic patch only** — not a production fix.

**Symptom (demonstrated):** After S2, SoundWire OK, `force_fw_reinit()` / `fw_ready success=1`, PCM `RUNNING`, `hw_ptr` advances, PipeWire and direct ALSA agree, `amixer` does not recover audio.

**Hypothesis (not proven):** After `tas2783_fw_reinit()`, ASoC software state may remain internally consistent while the TAS2783 functional state no longer matches playback expectations (PCM active, no analog output). One plausible mechanism is that the POST_PMU path (including `FU_MUTE=0` on FU21/FU23) does not re-run after firmware reload.

Case C audible PASS: [w2b-prime-case-c-20260712.md](w2b-prime-case-c-20260712.md).

---

## What is demonstrated vs hypothesized

| Demonstrated | Hypothesized |
|--------------|--------------|
| SDW + FW ladder OK post-S2 | DAPM / FU_MUTE desync after `fw_reinit` |
| PCM RUNNING + hw_ptr | `success=1` = download done, not DSP audibly ready |
| Same symptom PW vs ALSA | Case C vs today = state/regression, not stack invalid |

---

## Patch

`research/make-it-work/patches/w3-dapm-diagnostic.patch` on **upstream series B + W2**.

Build:

```bash
sudo ./scripts/build-w3-dapm-probe.sh
sudo reboot
```

---

## Experiment A — instrumentation only (default)

Module param `w3_dapm_sync_probe=0` (default).

1. Cold boot — confirm audible.
2. `./scripts/post-s2-playback-snapshot.sh --label pass-cold`
3. `systemctl suspend` → wait ~20 s.
4. `speaker-test -D hw:1,2 -c 2 -t sine -f 440 -l 1` (ear check).
5. `./scripts/post-s2-playback-snapshot.sh --label fail-silent`
6. Collect W3 trace:

```bash
journalctl -k -b 0 | grep 'W3 ctx='
```

**Look for:**

| Log | Question |
|-----|----------|
| `W3 ctx=fw fn=fw_reinit` | Confirms path is `tas_io_init` only (no DAPM callbacks) |
| `W3 ctx=dapm tag=post-fw_reinit widget=FU21 power=…` | Are FU21/FU23/SPK ON while silent? |
| `W3 ctx=dapm fn=fu21_event event=…` | Does POST_PMU fire on first playback after S2? |

Compare with `./scripts/post-s2-playback-snapshot.sh --label pass-cold` DAPM section (debugfs).

---

## Experiment B — minimal functional probe

**Only after Experiment A on same build.**

```bash
echo 1 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe
systemctl suspend
sleep 20
speaker-test -D hw:1,2 -c 2 -t sine -f 440 -l 1
journalctl -k -b 0 --since '2 min ago' | grep 'W3 ctx=dapm fn=sync'
```

| Hear tone? | Interpretation |
|------------|----------------|
| **Yes** | Strong correlation — DAPM resync needed after `fw_reinit`; design targeted fix |
| **No** | DAPM-only hypothesis weakened; next: PDE23 power, SDCA readback, DSP state |

Reset param: `echo 0 | sudo tee /sys/module/snd_soc_tas2783_sdw/parameters/w3_dapm_sync_probe`

---

## Experiment C — if B works

Understand **why** sync was needed: diff `pre-sync` vs `post-sync` widget lines in dmesg; check whether POST_PMU events appear after sync + playback.

---

## `tas2783_fw_reinit()` today (series B + W2)

Calls only:

```text
invalidate fw flags → tas_io_init() → SW reset → request_firmware → init writes
```

Does **not** call: `set_bias_level`, `dapm_power_widgets`, or `tas_fu21_event` / `tas_fu23_event`.

W3 logs confirm this at runtime.

---

## References

- [silent-playback-dapm-fu-mute-20260712.md](silent-playback-dapm-fu-mute-20260712.md)
- [w2-force-fw-reinit.patch](../make-it-work/patches/w2-force-fw-reinit.patch)
- Snapshot: `scripts/post-s2-playback-snapshot.sh`
