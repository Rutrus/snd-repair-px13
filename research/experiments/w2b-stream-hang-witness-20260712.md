# Stream hang witness — wait_for_avail snapshot (2026-07-12)

English (canonical). Case C′ first capture while `speaker-test` blocked post-S2 (px13 off, W1+W2).

**Tool:** `resolution/scripts/witness-stream-hang.sh` · **time:** 13:19:55 · **PID:** 24172

**Follow-up protocol:** [w2b-hwptr-stall-protocol.md](w2b-hwptr-stall-protocol.md) — pointer time series + IRQ delta required before strong conclusions.

---

## Proven facts

| Observation | Evidence |
|-------------|----------|
| `hw_params` / SDW program OK | 13:19:39 `sdw_program_params ret=0` |
| Audible playback | user report |
| PCM `RUNNING` | status sysfs |
| `appl_ptr` ≫ `hw_ptr` (delay 7856) | single snapshot |
| Blocked in `wait_for_avail` | wchan + stack |

---

## Not proven (single snapshot)

We **cannot** yet distinguish:

- IRQ not delivered vs DMA stopped vs SDW not consuming vs driver not updating `hw_ptr` vs sync wait

All match: `RUNNING` + lagging `hw_ptr` + `wait_for_avail`.

**Avoid:** claiming “period interrupts / DMA stopped” until [hw_ptr stall protocol](w2b-hwptr-stall-protocol.md) classifies A/B/C and IRQ vs pointer correlation.

---

## Snapshot at hang (13:19:55)

**Userspace:**

```text
wchan: wait_for_avail [snd_pcm]
stack: wait_for_avail → __snd_pcm_lib_xfer → snd_pcm_ioctl
```

**PCM2:**

```text
state: RUNNING  owner_pid: 24172
delay: 7856  avail: 336
hw_ptr: 83200  appl_ptr: 91056
```

**Kernel (13:19:39):** ENZODBG all OK; no FW timeout, no deprepare.

---

## Investigation stage

```text
resume → ATTACHED → FW OK → hw_params OK → START OK → tone heard
                                              ↓
                              progress stops (mechanism TBD)
                                              ↓
                              wait_for_avail
```

This is **not** the same failure mode as pre-Case-C (no START). It is a **later-stage** stall — closer to a functional patch, last bottleneck TBD.

---

## References

- Case C PASS: [w2b-prime-case-c-20260712.md](w2b-prime-case-c-20260712.md)
- Next measurements: [w2b-hwptr-stall-protocol.md](w2b-hwptr-stall-protocol.md)
