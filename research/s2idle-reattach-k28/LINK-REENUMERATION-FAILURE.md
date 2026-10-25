# Link re-enumeration failure after manager reset (ACP70 / PX13)

English (canonical). Evidence from Phase 6 resume-window capture (run 0004, 2026-07-10).

See also: [SOUNDWIRE-BUS-CONTRACT.md](SOUNDWIRE-BUS-CONTRACT.md), [AMD-RESUME-PATHS.md](AMD-RESUME-PATHS.md), [SDW-INITIALIZATION-COMPLETE-MAP.md](SDW-INITIALIZATION-COMPLETE-MAP.md)

---

## Project shift (Phase 5 → Phase 6)

| Phase | Focus |
|-------|--------|
| 5 | TAS2783 codec lifecycle / firmware |
| **6** | **ACP70 SoundWire link re-enumeration after system resume** |

Codecs (RT721, TAS2783) are **witnesses** until AMD manager ping/status path is understood.

---

## Confirmed FAIL pattern (run 0004)

```text
suspend_entry
  runtime_resume  → branch_fast_path (codec PM, pre-reset)
  manager_reset   → dev=1,2,3 ATTACHED → UNATTACHED
  wait_init_start → wait_init_timeout (5 s)
  resume_exit ret=-110
suspend_exit
```

**Post `manager_reset`:** no `UNATTACHED → ATTACHED`, no `completion` for **any** slave.

---

## Causal chain (inverted from Phase 5)

```text
AMD manager (system_resume, POWER_OFF)
        │
        ▼
manager_reset → all slaves UNATTACHED
        │
        ▼
PING → status bitmap → queue_work → handle_status → sdw_handle_slave_status
        │                              (break anywhere = no re-attach)
        ▼
no completion(initialization_complete)
        │
        ▼
RT721 wait_init_timeout (-110) → TAS2783 never inits → Dummy Output
```

---

## Upstream framing (conservative)

**Observed:** after `manager_reset` on system resume, all slaves go `UNATTACHED` and **no** `ATTACHED`/`completion` appears in the instrumented window; RT721 times out on `initialization_complete()`.

**Hypothesis (pending AMD trace):** a step in the manager PING → `queue_work` → `handle_status` chain does not occur or reports empty status. Do not claim “broken re-enumeration” until FAIL-A/B/C is identified.

---

## Hypotheses A / B / C (working probabilities)

| ID | Break | ~% | Trace signature |
|----|-------|---:|-----------------|
| **A** | No IRQ / no `queue_work` after reset | 20 | Only `manager_reset` + timeout in window |
| **B** | Ping / `status[]` always UNATTACHED | 45 | `ping_status` + `handle_status st*=UNATTACHED`, `devmask=0` |
| **C** | HW ATTACHED but bus skips / no transition | 35 | `devmask≠0`, no bus `new=ATTACHED` or `state_skip` |

---

## Timing template (anchor: manager_reset t=+0)

Tool: [`scripts/phase6-resume-timeline.sh`](../../scripts/phase6-resume-timeline.sh)

**PASS (expected sketch):**

```text
t=+0 ms   manager_reset
t=+4 ms   ping_status resp=0x…
t=+6 ms   queue_work devmask=0x…
t=+8 ms   bus dev=N UNATTACHED→ATTACHED
t=+9 ms   completion dev=N
```

**FAIL A (no IRQ):**

```text
t=+0 ms   manager_reset
          (no ping / queue_work)
t=+5004 ms wait_init_timeout
```

**FAIL B (ping empty):**

```text
t=+0 ms   manager_reset
t=+4 ms   ping_status resp=0x…
t=+6 ms   handle_status st0..3=UNATTACHED
t=+5004 ms wait_init_timeout
```

Kernel AMD traces include `t=+Nms` when [`0003-phase6-amd-sdw-trace.patch`](proposed/0003-phase6-amd-sdw-trace.patch) is installed.

---

## Do not touch (until AMD path known)

- RT721 / TAS2783 codec drivers
- `soc_sdw_utils`, machine driver
- Behavior-changing “fixes”

---

## Build & capture

```bash
./scripts/build-phase6-sdw-trace.sh
./scripts/build-phase6-amd-trace.sh
./scripts/build-phase6-rt721-trace.sh
sudo reboot
./scripts/phase6-experiment.sh arm --notes run-N
systemctl suspend
./scripts/phase6-experiment.sh tl --last-resume   # or: timeline RUN_ID
./scripts/phase6-experiment.sh matrix --last-resume
```
