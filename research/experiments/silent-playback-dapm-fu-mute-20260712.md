# Silent playback post-S2 — functional mismatch hypothesis (2026-07-12)

English (canonical). **Branch A regression** — same W2 ladder as Case C PASS, no audible output.

---

## Demonstrated vs hypothesized

**Demonstrated** after S2 (snapshots: `validation/playback-snapshot-fail-silent-*`):

- SoundWire operational; `force_fw_reinit()` → `fw_ready success=1` (:8, :b)
- PCM `RUNNING`; `hw_ptr` advances; PipeWire ≡ ALSA direct
- `amixer` at max / switches ON does not restore audio

**Hypothesis (not proven):** After `tas2783_fw_reinit()`, ASoC software state may stay coherent while the TAS2783 functional state no longer matches playback expectations — PCM active, no analog output. A plausible mechanism is that the POST_PMU sequence (including `FU_MUTE=0` on FU21/FU23) does not re-execute after firmware reload.

Case C audible PASS: [w2b-prime-case-c-20260712.md](w2b-prime-case-c-20260712.md).

---

## Runs (2026-07-12)

| Time | Event | Audible |
|------|-------|---------|
| 16:52 | S2, W2 OK | NO |
| 17:06 | S2, W2 OK | NO |

---

## W3 diagnostic (next step)

See [w3-dapm-diagnostic-protocol.md](w3-dapm-diagnostic-protocol.md).

- Patch: `research/make-it-work/patches/w3-dapm-diagnostic.patch`
- Build: `scripts/build-w3-dapm-probe.sh`
- Snapshot: `scripts/post-s2-playback-snapshot.sh`

Experiments A (trace) → B (`snd_soc_dapm_sync` via module param) → C (explain sync).

---

## References

- W2: [w2-force-fw-reinit.patch](../make-it-work/patches/w2-force-fw-reinit.patch)
- Recovery incident: [post-s2-silent-playback-recovery-20260712.md](post-s2-silent-playback-recovery-20260712.md)
