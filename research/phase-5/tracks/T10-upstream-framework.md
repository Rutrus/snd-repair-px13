# T10 — Upstream / maintainer framing

## Shift

From:

> On ASUS ProArt PX13, `:8` fails after s2idle.

To:

> SoundWire/ASoC property **P** is violated when **condition C** occurs on system resume.

## Candidate properties (hypotheses — fill with evidence)

| Property P | Violated if | Evidence track |
|------------|-------------|----------------|
| Async FW complete before PCM open | hw_params without fw_ready | T02, T05 |
| Slave PM resume succeeds before stream setup | `-110` then done=0 | T06, T05 |
| FW reload on warm resume | fw_ready not re-run | T02, T03 |
| Per-slave independence | :b OK while :8 broken | T07 |

## Deliverable

Draft cover letter paragraph for future upstream series — **after** T01–T07, not before.

## Reference

- [`../../upstream/series-B-firmware/`](../../upstream/series-B-firmware/) — existing retry series; may be superseded or reframed
