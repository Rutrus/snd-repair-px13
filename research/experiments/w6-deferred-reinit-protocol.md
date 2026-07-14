# W6 — deferred second `fw_reinit` timing experiment

## Context (W5 conclusion)

W5 showed that **the same** `tas2783_fw_reinit()` works when invoked manually after post-S2 silence. W2’s first reinit on resume still leaves speakers silent. W6 tests **when** the second reinit must run — not **what** it does.

Open hypotheses:

1. **Timing** — first reinit runs before bus/clock/PLL is stable.
2. **Intermediate event** — something between W2 and W5 (runtime PM, SDW attach, amp power) must complete first.
3. **Ordering** — W2 runs before codec/DAPM/clock preconditions.

W6 phase 1 sweeps **delay ms**. Phase 2 uses **first port PRE_PREP** (stream setup) as an event-driven trigger.

## Build

```bash
sudo ./scripts/build-w6-deferred-reinit.sh
sudo reboot
```

Stack: upstream A+B+C + W2 + W4 + W4b + W5 + W6. Do **not** combine with `px13-audio-resume`.

## Module parameters

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `deferred_reinit_ms` | 0 | Schedule 2nd `fw_reinit` N ms after W2 (0 = disabled) |
| `deferred_reinit_on_port_prep` | 0 | 2nd reinit on first `port_prep` PRE_PREP after W2 |

Path: `/sys/module/snd_soc_tas2783_sdw/parameters/`

Mutually exclusive in practice: use **either** timer **or** port-prep mode.

## Phase 1 — delay sweep (minimal)

**Do not sweep 0–3000 ms until W5 reproducibility is confirmed** — see [w5-reproducibility-protocol.md](w5-reproducibility-protocol.md).

Minimal three-point test after W5 is 5/5:

```bash
sudo ./scripts/w6-minimal-sweep.sh --skip-0   # if delay=0 control already recorded
```

Points: **0** (control), **1500**, **3000** ms only.

Full sweep (optional later):

```bash
for ms in 0 200 500 1000 1500 3000; do
  sudo ./scripts/w6-deferred-reinit-sweep.sh --delay "$ms"
done
```

Expected kernel sequence (timer mode, per uid 8 and 11):

```
W2 ctx=tas fn=force_fw_reinit when=resume|update_status uid=N
W6 ctx=schedule fn=deferred_reinit uid=N delay_ms=M
... M ms later ...
W6 ctx=deferred fn=fw_reinit uid=N ret=0
```

### Interpretation matrix

| Curve shape | Implication |
|-------------|-------------|
| FAIL at 0, PASS from threshold T upward | Strong timing/sync evidence |
| PASS at all delays including 0 | W6 scheduling differs from W5 manual path; revisit |
| FAIL at all delays | Second reinit alone insufficient when automated; race or cancel bug |
| Inconsistent threshold across runs | Intermittent race; increase N and log SDW attach timestamps |

Document results in `validation/w6-delay-*` and a summary table in this file.

## Phase 2 — event-driven (port PRE_PREP)

Hypothesis: sync to **first playback stream setup** instead of fixed sleep.

```bash
sudo ./scripts/w6-deferred-reinit-sweep.sh --port-prep
```

Sequence:

```
W2 ctx=tas fn=force_fw_reinit ...
W6 ctx=arm fn=port_prep_reinit uid=N
... speaker-test opens PCM ...
W6 ctx=port_prep fn=fw_reinit uid=N ret=0
```

If port-prep mode PASS while timer mode needs ≥1 s, the fix should be **event-driven**, not `msleep`.

## Notes

- W2 always runs **first** reinit immediately (reproduces baseline FAIL at `deferred_reinit_ms=0`).
- W6 adds an **automatic** second reinit; W5 debugfs remains for manual control.
- During deferred reinit, playback may return `-EIO` (same as W5); wait for `W6 ctx=deferred ... ret=0` before judging audio.
- Pending work is cancelled on system suspend.

## Upstream path (after W6 data)

1. Publish delay threshold from phase 1.
2. If threshold stable, prototype deterministic trigger (SDW attach complete, first stream prep, or DAPM sync).
3. Upstream patch narrative: *first post-S2 reinit runs before device ready; deferred/event-aligned reinit restores output.*
