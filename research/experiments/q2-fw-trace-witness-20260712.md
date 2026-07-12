# Q2 witness — TAS2783Q2 trace after suspend/resume (2026-07-12)

English (canonical). **Consolidation witness** for Q2 H1–H4 and investigation handoff.

**Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`  
**Module:** `snd-soc-tas2783-sdw.ko` (upstream series B + Q2 trace patch)  
**Archive:** `validation/q2-fw-trace/snap-20260712T102620.log`, `snap-20260712T103837.log`  
**Prerequisite:** Q1 closed — [pcm-dual-path-trace-20260712.md](pcm-dual-path-trace-20260712.md)

---

## Executive summary

This run **closes Q2 for the observed resume cycle**: the async firmware ladder never starts because **no observable path reaches `tas_io_init()` before `hw_params()` times out**.

The **immediate precondition** missing in logs is a usable SoundWire attach transition (`status == ATTACHED`) after `manager_reset`. The **exact subsystem** within the re-attach flow (AMD manager, SoundWire core, ASoC machine, or their interaction) **remains open**.

**Investigation focus shifts** from TAS2783 firmware async to:

```text
PM resume
    ↓
AMD SoundWire manager / bus re-attach
    ↓
slave ATTACHED
    ↓
tas_update_status() → tas_io_init()
    ↓
request_firmware_nowait() → tas2783_fw_ready()
```

Everything after `ATTACHED` is largely explained by this witness for the captured cycle.

---

## Protocol

```bash
./scripts/build-q2-fw-trace.sh
sudo reboot
systemctl suspend
# resume
./scripts/q2-fw-trace-collect.sh
journalctl -k -b 0 | grep TAS2783Q2
```

---

## Demonstrated facts (maintainer-safe)

These may be cited as **observed on this boot / this resume cycle**.

| # | Fact | Evidence |
|---|------|----------|
| D1 | **Q1 chain reproduced with Q2 instrumentation** | `hw_params wait` → `fw download wait timeout in hw_params` → `error playback without fw download` → ASoC -22 on `:8` |
| D2 | **Codec flags stay cleared at hw_params wait** | `hw_params wait uid=0x8 success=0 done=0`; `wait_done waited=0 success=0 done=0` |
| D3 | **No `request_firmware_nowait()` observable before timeout** | No `fn=io_init nowait` anywhere after suspend |
| D4 | **`tas2783_fw_ready()` not observed** | No `fn=fw_ready enter` / `exit` / `nwrite_fail` after suspend |
| D5 | **`invalidate` runs on both UIDs at suspend** | `system_suspend invalidate uid=0x8` and `uid=0xb` @ 10:24:47 / 10:33:19 |
| D6 | **Slaves go UNATTACHED on suspend** | `update_status … status=0` after `manager_reset` |
| D7 | **Resume waits fail on both UIDs** | `resume: initialization timed out` → PM `-110` on `:8` and `:b` |
| D8 | **No ATTACHED transition before first hw_params wait** | `system_resume skip_reinit status=0`; `update_status skip_io_init status=0`; **no** `hw_params reinit` (gated on ATTACHED) |
| D9 | **S0 healthy on both UIDs** | Pre-suspend: `hw_init=1 success=1 done=1`, `skip_io_init` |

**Wording discipline:** D3–D4 prove **absence in the trace**, not a proof about every possible driver path on all hardware states.

---

## H1–H4 verdict (this cycle)

| ID | Verdict | Rationale |
|----|---------|-----------|
| **H1** | **Supported for this execution cycle** | No observable `fn=io_init enter`, `call_io_init`, or `fw_reinit enter` after suspend through first hw_params timeout |
| **H2** | **Ruled out (this cycle)** | No `nowait` line → no evidence `request_firmware_nowait()` ran |
| **H3** | **Ruled out (this cycle)** | No `fw_ready enter` → internal fw_ready failure cannot be observed |
| **H4** | **Ruled out (this cycle)** | No post-invalidate `exit success=1`; flags stay `success=0 done=0` until hw_params wait |

**Preferred H1 phrasing (upstream):**

> No observable invocation of `tas_io_init()` before the hw_params firmware wait timed out on this resume cycle.

Not: “H1 confirmed absolutely” or “io_init can never run.”

---

## Causal chain (observed + minimal inference)

### What the logs show (temporal order)

```text
10:24:47 / 10:33:19  system_suspend invalidate (:8, :b)
                    update_status status=0 (UNATTACHED, manager_reset)
                    resume: initialization timed out (-110) (:8, :b)

10:24:53+           hw_params wait success=0 done=0 (:8)
                    [~3 s] fw download wait timeout in hw_params
                    error playback without fw download → -EINVAL
```

### Causal ladder (careful wording)

```text
status != ATTACHED                          [D6, D8 — observed]
        ↓
no observable tas_io_init()                 [H1 — this cycle]
        ↓
no observable request_firmware_nowait()     [D3 / H2 ruled out]
        ↓
fw_dl_task_done remains false               [D2 — observed]
        ↓
hw_params waits until timeout → -EINVAL     [D1 — observed]
```

**Note:** `skip_io_init` and `skip_reinit` are **observed branch outcomes**, not root causes. They are consistent with — and likely **downstream of** — failed or incomplete bus re-attach after resume.

---

## Series B (0003) — demonstrated limitation (this scenario)

Patch 0003 assumes a path like:

```text
resume → slave ATTACHED → fw_reinit / io_init
```

Observed instead:

```text
resume → status = UNATTACHED → system_resume skip_reinit
       → update_status skip_io_init
       → hw_params reinit not taken (requires ATTACHED)
```

**Conclusion (this cycle):** 0003 cannot act when the slave never reaches ATTACHED, regardless of implementation quality inside the codec driver.

Retest 0003 remains valid **only after** a resume where `:8` logs `status=1` and attach completes.

---

## UID `:8` vs `:b`

| UID | Resume init timeout | hw_params FW timeout | Role |
|-----|---------------------|----------------------|------|
| `:8` | Yes (-110) | Yes (SmartAmp / PCM2) | Manifestation site |
| `:b` | Yes (-110) | Not exercised in playback probe | Same bus failure; not the failing PCM path |

Asymmetry in dmesg volume reflects **which path is probed**, not necessarily a `:8`-only hardware fault.

---

## What this witness does **not** prove

| Claim | Why not yet |
|-------|-------------|
| “Upstream bug is in AMD manager” | Re-attach failure observed; **first missing transition** not localized |
| “Break is at manager_reset” | `manager_reset` seen on suspend; **not proven** as first fail site |
| “SoundWire core is broken” | Same |
| “IRQ loss **causes** this attach failure” | Phase 6–8 not correlated same-boot in this capture |
| “0003 is useless on all resumes” | Only demonstrated when ATTACHED never returns |
| “H1 true on every future boot” | Single-cycle observational proof |

**Safe Q2 closure statement:**

> Q2 closed for this cycle: FW async never started because `status != ATTACHED` before `io_init`. Q3 open: first missing SoundWire re-attach transition after resume.

---

## Investigation handoff — Q3 (post-witness)

**Q2.5 (layer):** `io_init` never ran because `status != ATTACHED` — closed this cycle.

**Q3 (open):** What is the **first** transition in the SoundWire re-attach ladder that does not occur after resume? Do **not** assume `manager_reset`.

**Correlated same-boot (observed):** `initialization timed out (-110)` while `master_port OK` / port programming succeeds — **inference:** bus/master alive; slave init protocol incomplete.

Protocol: [../q2.5-sdw-reattach/README.md](../q2.5-sdw-reattach/README.md)

---

## Related

| Doc | Role |
|-----|------|
| [../q2-fw-resume/HYPOTHESES.md](../q2-fw-resume/HYPOTHESES.md) | H1–H4 matrix (updated) |
| [../UNIFIED-CAUSAL-MODEL.md](../UNIFIED-CAUSAL-MODEL.md) | Canonical model |
| [pcm-dual-path-trace-20260712.md](pcm-dual-path-trace-20260712.md) | Q1 witness |
