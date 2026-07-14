# W5 reproducibility protocol

English (canonical). **Run before W6 delay sweep.**

## What is already proven (single session)

| Step | Result |
|------|--------|
| W2 on resume | FAIL (silent, software OK) |
| W5 manual 2nd `fw_reinit()` | PASS (audible) |
| W6 `deferred_reinit_ms=0` | FAIL (control — same as W2 alone) |

That shows **a later second reinit can work**. It does **not** yet prove that **delay alone** is the fix.

## What we need now

Prove W5 is **reproducible** across multiple S2 cycles:

```text
S2 → silence → debugfs uid8 → debugfs uid11 → sleep 2s → speaker-test → ear PASS?
```

If **5/5 PASS**, the solid statement is:

> A second `fw_reinit()` triggered from userspace after post-S2 silence consistently restores audible playback.

That is stronger evidence than sweeping ten delay values.

## Run

```bash
sudo ./scripts/w5-reproducibility-test.sh --cycles 5
```

Optional: `--no-pre-play` skips the pre-W5 silence check (saves time).

Output: `validation/w5-repro-<timestamp>/cycle-N/`

Fill `audio=PASS|FAIL` in each cycle `meta.txt` if non-interactive.

## Interpretation

| Result | Meaning |
|--------|---------|
| 5/5 PASS | Proceed to W6 minimal (1500, 3000 ms) |
| Mixed | Intermittent race — capture W7 timeline each cycle |
| 0/N PASS | W5 no longer holds — check stack, module flavor, px13-resume |

## W7 timeline (optional, recommended)

Rebuild with W7 for millisecond anchors:

```bash
sudo ./scripts/build-w7-ts-trace.sh && sudo reboot
```

After each cycle:

```bash
./scripts/w7-ts-capture.sh --last-s2
```

Events logged (ms since first post-S2 resume anchor):

| Event | Meaning |
|-------|---------|
| `s2_resume_anchor` | t=0 reference |
| `w2_fw_reinit_start` / `_end` | W2 window |
| `first_hw_params` | First playback stream setup |
| `first_port_prep` | First SDW port PRE_PREP |
| `w5_fw_reinit_start` / `_end` | Manual reinit window |

Compare W2 end vs first_hw_params vs W5 start to see whether W5 succeeds due to **time**, **ordering**, or **execution context** (process context vs resume callback vs workqueue).

## Next step (only after W5 reproducible)

```bash
sudo ./scripts/w6-minimal-sweep.sh --skip-0   # if delay=0 already done
```

Three points only: **0**, **1500**, **3000** ms.

### Scenario A (timing)

```text
0      FAIL
1500   PASS
3000   PASS
```

### Scenario B (not delay alone)

```text
0      FAIL
1500   FAIL
3000   FAIL
```

Then W5 works for **context**, not timer — investigate what differs (debugfs write path, runtime PM idle, workqueues drained, etc.).

## References

- [w4-w6-tas2783-double-reinit-20260714.md](w4-w6-tas2783-double-reinit-20260714.md)
- [w6-deferred-reinit-protocol.md](w6-deferred-reinit-protocol.md)
