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

## Parameter

| Param | Default | Meaning |
|-------|---------|---------|
| `phase7_delay_ms` | `0` | Control (Phase 6 baseline — no sleep) |

Set **before each suspend** (runtime writable):

```bash
echo MS | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms
```

## Sweep values (fixed set)

```text
0    control
5    10   20   50   100
```

**Stop early:** if any value shows STAT≠0, handler, or ATTACHED → stop sweep and investigate that band.

**Stop criterion (full sweep):** if **all six values** show identical witness to control (`STAT=0`, no handler, FAIL-1), **archive 0005 as negative experiment** and proceed to re-kick (0006). Do not revisit delay without new evidence.

---

## Sweep protocol (one delay per clean boot)

Do **not** reuse the same boot for multiple delay values — `resume=2+` produces FAIL-2 cascades and incomparable state.

```text
set delay_ms
    ↓
reboot
    ↓
post-reboot --notes p7-0005-d{MS}
    ↓
exactly ONE suspend
    ↓
post-suspend → analyze
    ↓
reboot
    ↓
next delay_ms
```

Example:

```bash
/home/rutrus/snd_repair/scripts/build-phase7.sh --experiment delay-after-d0
sudo reboot

for MS in 0 5 10 20 50 100; do
  echo "$MS" | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms
  sudo reboot
  /home/rutrus/snd_repair/scripts/phase6-hunt.sh post-reboot --notes "p7-0005-d${MS}"
  systemctl suspend
  /home/rutrus/snd_repair/scripts/phase6-hunt.sh post-suspend --save-window
done
```

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

`delay_ms` is in the log line so hunt logs remain self-describing without relying on `--notes` alone.

Phase 6 baseline unchanged: `intr_stat_post_D0` is read **before** the delay.

---

## Precedent (kernel tree)

`amd_manager.c` resume path uses `read_poll_timeout` only — **no existing `msleep`** on POWER_OFF resume. This experiment is exploratory.

---

## Build

```bash
/home/rutrus/snd_repair/scripts/build-phase7.sh --experiment delay-after-d0
```

Use `build-phase7.sh`, not `build-phase6-amd-trace.sh`, while this experiment is active.
