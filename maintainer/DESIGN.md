# Patch design — post-sleep hw_params reinit

English · maintainer summary.

---

## State machine

```text
system_suspend:
    post_system_sleep = true
    resume_playback_reinit_pending = false
    invalidate fw bookkeeping

resume / update_status(ATTACHED):
    fw_reinit()                              # first (resume-phase)
    resume_playback_reinit_pending = true    # if ret == 0

first hw_params after sleep:
    if resume_playback_reinit_pending:
        fw_reinit()                          # second (playback-phase)
        resume_playback_reinit_pending = false

later hw_params:
    (no extra reinit)

UNATTACHED / suspend:
    resume_playback_reinit_pending = false
```

---

## Patch file

`patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch`

Applied at build time by `scripts/apply-upstream-post-sleep-hw-params.py` on `tas2783-sdw.c` (after upstream series B sleep reload is present).

---

## Why hw_params

First real playback stream setup: PCM open, port prep, DAPM for stream, clocks active. Resume-path reinit runs **before** this milestone.

---

## Alternatives rejected

| Approach | Why not upstream |
|----------|------------------|
| `msleep(3000)` | Magic delay; worked as readiness proxy only |
| debugfs manual reinit | Not automatic |
| Reinit on every hw_params | Unacceptable overhead |

---

## Test plan

1. Cold boot stereo PASS  
2. S2 → playback audible  
3. S2 × 3  
4. Second stream open same boot — no redundant full reinit  
5. Jack + capture regression  

---

## Related patches on PX13

| Patch | Role |
|-------|------|
| upstream series B | First FW reload after sleep (still functionally insufficient alone) |
| `0002-amd-soundwire-resume-irq-kick` | SoundWire ATTACHED after S2 |
| This patch | Audible playback after S2 |
