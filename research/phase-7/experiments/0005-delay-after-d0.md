# Experiment 0005 — delay after D0 (falsification)

English (canonical). **NOT a fix proposal** — a **falsification experiment** to reject or narrow the timing-after-D0 hypothesis.

Patch: [../proposed/0005-delay-after-d0.patch](../proposed/0005-delay-after-d0.patch)

---

## Hypothesis

> The ACP70 SoundWire bring-up requires additional settling time after reaching D0 before the first interrupt can be generated.

## Expected outcome (falsification)

> If delays up to 100 ms produce **no change** in `ACP_EXTERNAL_INTR_STAT`, IRQ handler entry, or slave attachment, the **timing hypothesis is rejected** for this resume path.

A negative result is **valuable** — it closes an entire hypothesis family, not a failed fix attempt.

---

## Parameter persistence (critical)

`echo MS > /sys/module/soundwire_amd/parameters/phase7_delay_ms` **does not survive reboot**.

The module loads during boot with default `phase7_delay_ms=0`. Use **modprobe.d** so the value applies at load time:

```text
/etc/modprobe.d/snd-repair-phase7.conf
  options soundwire_amd phase7_delay_ms=MS
```

**Always verify after login, before suspend:**

```bash
/home/rutrus/snd_repair/scripts/phase7-sweep-post.sh --verify-only
```

Checks **running vs installed** `soundwire_amd` srcversion (stale module after `build-phase7.sh` without reboot is the usual failure), **modprobe.d**, and sysfs when present.

If verify fails, **do not suspend** — the run would be invalid.

---

## Sweep values (fixed set)

```text
0    control
5    10   20   50   100
```

**Stop early:** STAT≠0, handler, or ATTACHED → stop sweep, investigate band.

**Stop criterion (full sweep):** all six identical to control → **archive 0005 as negative experiment** → re-kick (0006).

### More delay is not “free”

A blind `msleep` after D0 is **not** guaranteed harmless or sufficient:

- It reads the same register **after** waiting — it does not kick the block or fix IRQ routing.
- Run **d20** (below) already shows **side effects without progress**: `intr_stat_post_D0=0x0` → `intr_stat_post_delay=0x4`, still **no** `irq_handler_enter`, **no** ATTACHED.
- Longer delays may expose latent STAT bits, change race windows, or **mask** a missing kick — not the same as “more time always helps.”

Continue the fixed sweep (50, 100) only on **clean boots** (`resume=1`) to map the band; do not assume monotonic improvement.

---

## Sweep protocol (one delay per clean boot)

**Do not** put `reboot` in a loop with steps after it — the shell dies on reboot.

**Do not** reuse one boot for multiple delay values (`resume=2+` → FAIL-2 cascades).

### Per sweep point (manual two-step)

**Step A — before reboot:**

```bash
/home/rutrus/snd_repair/scripts/phase7-sweep-pre.sh 20
# → writes modprobe.d + state, reboots (ends here)
```

**Step B — after login:**

```bash
/home/rutrus/snd_repair/scripts/phase7-sweep-post.sh --verify-only
/home/rutrus/snd_repair/scripts/phase7-sweep-post.sh
systemctl suspend
# after wake:
/home/rutrus/snd_repair/scripts/phase7-sweep-post.sh --after-suspend
```

**Step C — next delay:** repeat from Step A with next MS.

Full sweep order: `0`, `5`, `10`, `20`, `50`, `100` — six boots, six single suspends.

When done:

```bash
/home/rutrus/snd_repair/scripts/phase7-sweep-clear.sh && sudo reboot
```

---

## Same-boot alternative (no reboot between set and suspend)

If you only need **one** delay value without a clean-boot sweep:

```bash
echo 20 | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-reboot --notes p7-0005-d20
systemctl suspend
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-suspend --save-window
```

Use this for ad-hoc tests only — **not** for the formal 0–100 ms sweep (needs `resume=1` via reboot + modprobe.d).

---

## Success criteria (escalated — audio not required)

| Outcome | Interpretation |
|---------|----------------|
| `intr_stat_post_delay=0`, no handler, FAIL-1 | No effect at this N — continue sweep |
| STAT≠0, no handler | Shift to IRQ/routing hypothesis |
| `irq_handler_enter` | **Stop sweep** — timing band relevant |
| ATTACHED / completion | Delay affects bring-up |
| Audio OK | Strong hint — still not a production fix |

---

## Log probes

```text
PHASE7 ctx=amd fn=delay_after_D0 link=%d resume=%d delay_ms=%u
PHASE7 ctx=amd fn=intr_stat_post_delay link=%d resume=%d delay_ms=%u stat=0x%x
```

Phase 6 baseline unchanged: `intr_stat_post_D0` is read **before** the delay.

---

## Build (once)

```bash
/home/rutrus/snd_repair/scripts/build-phase7.sh --experiment delay-after-d0
sudo reboot
```

Use `build-phase7.sh`, not `build-phase6-amd-trace.sh`, while this experiment is active.

---

## Runs

| Run | delay_ms | resume_n | intr_stat_post_D0 | intr_stat_post_delay | handler | witness | Valid sweep? | Notes |
|-----|----------|----------|-------------------|----------------------|---------|---------|--------------|-------|
| p7-0005-d20 | 20 | 3 | 0x0 | **0x4** | NO | PARTIAL | **No** — `resume≠1`; repeat on clean boot | STAT changed without handler; log: `validation/phase6-runs/hunt-p7-0005-d20/` |

**d20 takeaway:** timing **does** affect the post-D0 STAT read (0→4 at 20 ms) but does **not** produce the first HW event path (handler / attach). Not a fix; narrows “pure settling” vs “STAT without delivery.”
