# 0001b — post-resume dual-trigger `fw_reinit` (Case A′)

**Status:** implemented (apply script + build path)  
**Depends on:** 0001 + upstream series B (`tas2783_fw_reinit`)  
**Module:** `snd-soc-tas2783-sdw`  
**Related:** [CASE-A-OPEN-STREAM-MUTE-20260722.md](CASE-A-OPEN-STREAM-MUTE-20260722.md)

English (canonical).

---

## Problem framing

0001 is not wrong; its **event model was incomplete**.

> 0001 assumes an event (`hw_params`) that the modern PipeWire stack no longer guarantees when a playback path stays open across s2idle.

Precise claim (upstream-safe wording):

> After wake we do **not** observe the codec `hw_params` path that 0001 needs to run the second `fw_reinit`. PipeWire may recover `hw:amdsoundwire,2p` in place (Broken pipe) while PCM stays `RUNNING`.

---

## Model (two triggers, one run)

```text
resume
  → first fw_reinit()
  → resume_playback_reinit_pending = true
  → schedule_delayed_work(post_resume_fw_reinit, ~100 ms)

        hw_params ──────┐
                        ├──► tas2783_run_post_resume_fw_reinit_once()
        delayed_work ───┘         │
                                  ├─ pending?
                                  ├─ ATTACHED?
                                  ├─ fw_dl_success?
                                  └─ claim + fw_reinit() once
```

- If `hw_params` wins → cancels delayed work inside `run_once`.  
- If `hw_params` never arrives → delayed work performs the same second reinit.  
- No duplicate reinits.

Naming: **`post_resume_fw_reinit`** / `run_post_resume_fw_reinit_once` — completion of resume pipeline, not a “magic delay”.

Delay: **`TAS2783_POST_RESUME_COMPLETION_MS 100`** (~`HZ/10`) — resume pipeline settle (incl. 0003b attach), not a measured physical constant.

---

## Evolution vs 0001

| | 0001 | 0001b |
|--|------|-------|
| Case | new stream after wake | stream already open / recovered |
| Trigger | `hw_params` only | `hw_params` **or** post-resume work |
| Core action | second `fw_reinit` | **same** via `run_once` |

---

## Apply / build

```bash
# after upstream A+B+C on tree:
python3 scripts/apply-upstream-post-sleep-hw-params.py "$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
python3 scripts/apply-0001b-post-resume-fw-reinit.py "$KERNEL_SRC/sound/soc/codecs/tas2783-sdw.c"
# or:
./scripts/build-upstream-post-sleep-reinit.sh
sudo ./scripts/snd-repair install-modules
# reboot
```

Markers in `.ko`:

- 0001: `post-sleep playback fw_reinit failed`
- 0001b: `snd_repair post-resume fw_reinit`

---

## Validation

1. Firefox (or continuous playback) on Speaker.  
2. One s2idle — **do not** change output device.  
3. Expect: Attached + 0003b kick delayed; dmesg `snd_repair post-resume fw_reinit`; **audible** audio.

Regression: silent machine → S2 → `speaker-test` still OK (`hw_params` or work may win).
