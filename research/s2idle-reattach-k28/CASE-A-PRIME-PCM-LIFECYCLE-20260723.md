# Case A′′ — 0001b ran, still mute; reopen restores audio

**Date:** 2026-07-23  
**Host:** colosal3 · k28 · overlay 0001b+0003b loaded  
**Branch:** `research/s2idle-sdw-reattach-k28`

English (canonical).

---

## Verdict

**Do not harden 0001b** (no third `fw_reinit`, no longer delay).

Evidence 2026-07-23:

| Step | Result |
|------|--------|
| Overnight S2 | 0003b kick delayed `pend=0x4` — Case B PASS |
| Same wake | `snd_repair post-resume fw_reinit` on `:8` and `:b` — **0001b executed** |
| Hours later | Attached, PCM `RUNNING`, Speaker `*`, **silent** |
| PipeWire restart + sink flip | **audible** again |

So the second `fw_reinit` is **not** a sufficient condition for audible output when the PipeWire PCM stays alive across s2idle.

Precise claim:

> After wake, 0001b’s second `fw_reinit` can complete successfully while the playback path remains silent until a **full PCM reopen** (close→open lifecycle), not merely until another `hw_params`.

---

## Two scenarios

### Scenario 1 — 0001b enough

```text
S2 → 0001b fw_reinit → audible
```

### Scenario 2 — 0001b necessary but not sufficient (this incident)

```text
S2
  → 0003b ATTACHED
  → 0001b second fw_reinit          # observed in dmesg
  → PCM never fully torn down
  → prepare / trigger(START) / port_prep may not re-run
  → mute despite RUNNING
  → sink flip / PW restart
  → close → hw_free → … → open → hw_params → prepare → trigger(START)
  → audible
```

0001b still fixes a **subset** (new or reopened streams that never get `hw_params`). Scenario 2 needs a **different anchor event**.

---

## What reopen actually does

Not “another `hw_params` only”:

```text
close → hw_free → trigger(STOP) → shutdown
-------------------------------------------
open → startup → hw_params → prepare → trigger(START)
(+ SoundWire port_prep on TAS2783)
```

Until now the product hook assumed `hw_params` was the restoring event. This incident falsifies “`hw_params` / second `fw_reinit` alone ⇒ audio”.

---

## Next binary question (before any 0001c)

> Which callback differs between **“0001b PASS but mute”** and **“reopen → audible”**?

Instrument (observation-only), marker `snd_repair pcm:`:

| Callback | Role |
|----------|------|
| `startup` | stream open |
| `hw_params` | rate/format/channels (+ existing 0001/0001b gates) |
| `prepare` | **prime suspect** — clocks / path / DSP arm |
| `trigger START/STOP/…` | stream run state |
| `hw_free` / `shutdown` | teardown |
| `port_prep` (SDW) | TAS requires explicit port prepare for playback |

**Do not** add another delayed `fw_reinit` until this contrast exists.

### Experiment E-PCM1

1. Build with PCM lifecycle trace (see apply script below).  
2. Cold boot → playback OK.  
3. S2 with Firefox open → if mute: capture dmesg from resume through mute window.  
4. Flip sink or restart PipeWire → capture until audible.  
5. Diff: which `snd_repair pcm:` lines appear **only** in step 4?

| Diff pattern | Next product hook candidate |
|--------------|----------------------------|
| `prepare` only on reopen | 0001c @ DAI `prepare` (or force prepare path) |
| `trigger START` only on reopen | hook / kick at START |
| `port_prep` only on reopen | SDW port_prep / stream re-prepare |
| teardown+full open only | may need userspace reopen or card-level reset — not more fw_reinit timers |

---

## Apply / build (research overlay)

```bash
# tree must already have 0001 + 0001b
python3 scripts/apply-pcm-lifecycle-trace.py "$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
./scripts/build-upstream-post-sleep-reinit.sh   # or rebuild tas module only
sudo ./scripts/snd-repair install-modules && sudo reboot
```

Capture:

```bash
journalctl -k -b 0 | grep 'snd_repair pcm:'
```

---

## Relation to 0001 / 0001b

| Patch | Keeps |
|-------|--------|
| 0001 | second reinit when `hw_params` arrives |
| 0001b | same when `hw_params` never arrives (open stream) |
| **not yet** | restore when reinit ran but pipeline never re-`prepare`/`START`s |

Upstream framing later: separate “firmware reinit after sleep” from “PCM path not restarted after sleep while stream handle kept”.
