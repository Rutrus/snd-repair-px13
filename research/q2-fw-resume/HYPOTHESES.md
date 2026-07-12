# Q2 — Firmware async hypotheses (H1–H4)

English (canonical). Discriminate **why `fw_dl_success` stays false** after resume.

**Prerequisite:** Q1 closed — [../experiments/pcm-dual-path-trace-20260712.md](../experiments/pcm-dual-path-trace-20260712.md)

---

## Q1 — first observable manifestation (practically closed)

Q1 identifies **where the kernel first reports inconsistent state**, not necessarily where the bug originates.

```text
resume
    ↓
tas_sdw_hw_params()
    ↓
fw download wait timeout in hw_params
    ↓
error playback without fw download
    ↓
-EINVAL → PCM2 dead → Dummy
```

Upstream-safe wording: *“async firmware completion did not succeed before hw_params on UID :8.”*

---

## Q2 — binary question

> **Does `tas2783_fw_ready()` run on this resume cycle?**

Execution ladder:

```text
resume
    ↓
tas_update_status()
    ↓
tas_io_init()
    ↓
request_firmware_nowait()
    ↓
tas2783_fw_ready()
    ↓
fw_dl_success = true
```

If the trace breaks at any rung, the next investigation is localized to that rung only.

---

## H1–H4 matrix

| ID | Model | `TAS2783Q2` signature | ~weight (engineering, not statistical) |
|----|-------|----------------------|----------------------------------------|
| **H1** | `tas_io_init()` never runs | No `fn=io_init enter` after resume | **medium** |
| **H2** | `nowait` OK, callback never runs | `nowait ret=0`, **no** `fw_ready enter` | **medium–high** |
| **H3** | `fw_ready` runs, fails before `success=true` | `fw_ready enter` + `exit … success=0` (+ `nwrite_fail rc=…`) | **medium** |
| **H4** | `success=1` then cleared | `exit success=1` then invalidate without new ready | **low** |

**Why H4 is low:** `fw download wait timeout in hw_params` fits *“waiting for completion that never arrives”* better than *“completion arrived then state was cleared”*. Not ruled out — needs `exit success=1` evidence.

**Q2 witness (2026-07-12):** [../experiments/q2-fw-trace-witness-20260712.md](../experiments/q2-fw-trace-witness-20260712.md)

| ID | Verdict (this cycle) |
|----|----------------------|
| H1 | **Supported** — no observable `io_init` before hw_params timeout |
| H2 | **Ruled out** — no `nowait` |
| H3 | **Ruled out** — no `fw_ready enter` |
| H4 | **Ruled out** — no post-invalidate `success=1` |

Use **“this execution cycle”** wording in upstream mail; logs prove observational absence, not all driver paths.

### H3 sub-cases (if `fw_ready enter` appears)

| `fw_ready exit` fields | Likely failure |
|------------------------|----------------|
| `fmw_ok=0` | Firmware file not loaded in callback |
| `nwrite_fail rc=-110` | SoundWire write timeout during download |
| `cur_file=0 ret=-EINVAL` | Empty / malformed image |
| `ret=0 success=1` | H3 ruled out for this cycle |

---

## Secondary lines — consequence, not cause (documented)

### `SDW: Invalid device for paging :0`

Observed **after** fw timeout and `sdw_deprepare_stream: inconsistent state state 6` in [../experiments/pcm-dual-path-trace-20260712.md](../experiments/pcm-dual-path-trace-20260712.md).

**Interpretation (temporal order A — default):**

```text
hw_params abort / timeout
    ↓
sdw_deprepare_stream (inconsistent state)
    ↓
Invalid device for paging :0   ← consequence
```

Do **not** cite paging errors as root cause unless a future trace shows paging **before** fw timeout (order B).

---

## Demonstrated vs not demonstrated

| Demonstrated (2026-07-12 Q2 witness) | Not demonstrated |
|--------------------------------------|------------------|
| Q1 manifestation chain | Which subsystem fails re-attach (manager vs core vs machine) |
| No observable `nowait` / `fw_ready` this cycle | H1 on every possible hardware state |
| Codec `success=0 done=0` at hw_params wait | IRQ **causes** attach failure (needs same-boot correlation) |
| Both `:8` and `:b` resume init timeout | 0003 fixes resume when ATTACHED never returns |
| `skip_io_init` / `skip_reinit` when `status=0` | `skip_*` as root cause (likely consequence) |
| Paging after timeout → **consequence** | 0003 effect when ATTACHED **does** return |

---

## Instrumentation

Patch: `patches/0001-tas2783-q2-resume-trace.patch` — regenerate if apply fails: `./scripts/regenerate-q2-fw-trace-patch.sh`

`fw_ready exit` logs: `ret`, `cur_file`, `fmw_ok`, `success`, `done`; `nwrite_fail` on `sdw_nwrite_no_pm` error.

```bash
./scripts/build-q2-fw-trace.sh
sudo reboot
./scripts/q2-fw-trace-collect.sh --label boot
systemctl suspend
./scripts/q2-fw-trace-collect.sh --label after-resume
journalctl -k -b 0 | grep TAS2783Q2
```

---

## UID asymmetry (`:8` vs `:b`)

Q1 showed **`:8` only**. Q2 trace must log both UIDs — may explain historical matrix asymmetry.

---

## Related

- [README.md](README.md)
- [../UNIFIED-CAUSAL-MODEL.md](../UNIFIED-CAUSAL-MODEL.md)
- [../tas2783-fw_dl_success-map.md](../tas2783-fw_dl_success-map.md)
