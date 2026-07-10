# RT721 Phase 6 instrumentation

Observation-only kernel trace for the RT721 SoundWire codec PM resume path. Goal: explain **why** PASS and FAIL diverge at `initialization_complete` / `-ETIMEDOUT`, not merely document the timeout.

**Patch:** [`proposed/0001-phase6-rt721-pm-trace.patch`](proposed/0001-phase6-rt721-pm-trace.patch)  
**Build:** [`../../scripts/build-phase6-rt721-trace.sh`](../../scripts/build-phase6-rt721-trace.sh)

No behavior change. TAS2783 is out of scope for this step.

---

## Resume chronology (target)

```text
PM resume
    ↓
rt721_sdca_dev_resume()          fn=resume_enter
    ↓
branch: unattach_request?
    ├─ fast path (no wait)       fn=branch_fast_path → sdw_write → regmap_sync
    └─ wait path                 fn=wait_init_start
           ↓
       initialization_complete   fn=wait_init_ok | fn=wait_init_timeout
           ↓
       regmap_sync               fn=regmap_sync_start / _done
           ↓
       return                    fn=resume_exit ret=…
```

Parallel SDW callbacks during the wait window:

```text
update_status_attached / _unattached
    ↓
io_init_call → io_init_enter → io_init_done
```

All `ctx=pm` lines include `t=+Nms` relative to `resume_enter`. `ctx=init` lines use the same anchor when resume is active.

---

## Questions this answers

| # | Question | Trace markers |
|---|----------|---------------|
| 1 | Does `resume()` run on FAIL? | `resume_enter` vs absent |
| 2 | Same path but slower? | Compare `t=+…ms` on `resume_exit` PASS vs FAIL |
| 3 | First SDW / attach during wait? | `update_status_*`, `io_init_*` timestamps vs `wait_init_*` |
| 4 | Does callback finish? | `resume_exit ret=0` vs `ret=-110` after `wait_init_timeout` |
| 5 | Fast path vs wait path? | `branch_fast_path` vs `wait_init_start` + `unattach_req=1` at enter |

---

## H5 (timing hypothesis)

The driver waits up to **5000 ms** on `initialization_complete`. Observed FAIL at ~0 ms in Phase 6 kmsg is the **PM failure surfacing immediately after resume**, not proof the wait lasted 5 s.

Compare:

- `wait_init_ok remaining_ms=…` — how much of the 5 s budget remained when attach completed (PASS).
- `wait_init_timeout` with no prior `update_status_attached` — bus never re-attached during wait (FAIL).
- `resume_exit` total latency: if PASS ≈ 78 ms and FAIL ≈ 5000 ms, the wait expired; if FAIL also ≈ few ms, failure may be elsewhere in the PM stack.

---

## Experiment protocol

1. **Reboot** if RT721 or `:8`/`:b` are stuck Unattached.
2. Install trace module: `./scripts/build-phase6-rt721-trace.sh` → reboot.
3. Optional — reduce userspace noise:

   ```bash
   sudo systemctl mask --runtime px13-audio-fix.service 2>/dev/null || true
   export PHASE6_SKIP_PX13=1
   ```

4. Capture 2–3 comparable pairs:

   ```bash
   ./scripts/phase6-experiment.sh baseline --notes pre
   PHASE6_SKIP_PX13=1 ./scripts/phase6-experiment.sh arm --notes pass-candidate
   systemctl suspend
   # wait ≥65 s, confirm audio manually
   ./scripts/phase6-experiment.sh status
   ```

5. Extract kernel trace:

   ```bash
   journalctl -k -b 0 | grep 'PHASE6 ctx='
   ./scripts/phase6-experiment.sh diff 0002 0001   # example PASS vs FAIL
   ```

6. Write the Phase 6 report **only after** comparing RT721 `t=+…ms` timelines across pairs.

---

## Parse integration

`scripts/phase6-events-parse.sh` maps `PHASE6 ctx=pm|init|sdw` lines into `validation/phase6-events.csv` for diff/diagram tooling.

Priority milestones for `phase6-first-divergence.sh`: `wait_init_timeout`, `pm_fail_110`, `update_status_attached`, then TAS2783 events.

---

## Probability note (working estimate)

| Layer | Approx. |
|-------|--------:|
| RT721 PM / resume | 50–60% |
| SoundWire core / link after resume | 25–35% |
| ACP70 / AMD controller | 10–20% |
| TAS2783 | <5% |

These are hypotheses to test with this instrumentation, not conclusions.
