# Case C′ — hw_ptr progress protocol (post-START stall)

English (canonical). **No kernel code changes** until this protocol completes at least once.

**Prerequisite:** Case C PASS — W1+W2, px13 off, audible post-S2 ([w2b-prime-case-c-20260712.md](w2b-prime-case-c-20260712.md)).

---

## Question shift

```text
Before:  Can we start playback?     → START ✓ (proven)
Now:     What stops progress?       → characterize hw_ptr + IRQ
```

---

## Proven facts (2026-07-12 witness)

| Fact | Source |
|------|--------|
| `hw_params` succeeds | kernel ENZODBG / no -EINVAL |
| Audible tone | user |
| PCM `RUNNING` | `/proc/asound/card1/pcm2p/sub0/status` |
| `appl_ptr` far ahead of `hw_ptr` | status snapshot |
| Process in `wait_for_avail()` | `/proc/PID/stack` |

---

## Not yet proven (hypotheses — same symptom)

`hw_ptr` not advancing **may** be caused by:

1. Period interrupts not delivered (plausible)
2. DMA engine stopped
3. SoundWire stopped consuming
4. Driver not updating `hw_ptr` while HW still runs
5. Pipeline waiting on a sync event

All produce: `RUNNING` + fixed or lagging `hw_ptr` + growing `appl_ptr` + `wait_for_avail`.

**Do not** conclude “DMA/IRQ broken” until pointer + IRQ time series classify the stall.

---

## Procedure while hung

Terminal 1 — leave `speaker-test` blocked.

Terminal 2 — **while terminal 1 is still blocked** (not after Ctrl+C):

```bash
sudo ./resolution/scripts/witness-stream-hang.sh
# or: sudo ./resolution/scripts/witness-stream-hang.sh <PID>
# env: WITNESS_PTR_SAMPLES=25 WITNESS_PTR_INTERVAL_MS=500
```

If you see `pid=none` and `PCM2 state=closed`, the hang already ended — re-run `speaker-test` and capture again.

Or manual watch (20–30 s):

```bash
watch -n0.5 'grep -E "state|hw_ptr|appl_ptr|avail|delay" /proc/asound/card1/pcm2p/sub0/status'
```

Terminal 3 — IRQ counters (two snapshots 20 s apart):

```bash
grep -E 'snd|acp|sound|160:' /proc/interrupts | tee /tmp/irq1.txt
sleep 20
grep -E 'snd|acp|sound|160:' /proc/interrupts | tee /tmp/irq2.txt
diff /tmp/irq1.txt /tmp/irq2.txt
```

---

## Classification (pointer progress)

| Class | `hw_ptr` over 20–30 s | `appl_ptr` over same window | Meaning |
|-------|------------------------|----------------------------|---------|
| **A** | constant | constant | Process asleep in `wait_for_avail`; buffer full, no drain |
| **B** | increases slowly | may be constant | Starvation / back-pressure, not hard freeze |
| **C** | never changes | was ahead before sleep | Engine not advancing — strongest stall signal |

Only **Class C** supports “motor stopped”. Class B → starvation. Class A → already blocked, confirm C with pre-block samples if possible.

---

## Classification (IRQ vs hw_ptr)

| IRQ counters | `hw_ptr` | Interpretation |
|--------------|----------|----------------|
| increasing | frozen | Driver / pointer update path — not “no interrupts at all” |
| frozen | frozen | ACP/DMA/IRQ boundary — aligns with Branch B |
| increasing | increasing slowly | Starvation downstream of IRQ |

---

## Kill sequence (after capture)

Record which signal unblocks: `INT` → `TERM` → `KILL`. Then:

```bash
journalctl -k -b 0 --since '5 min ago' | grep -iE 'deprepare|trigger|stop|hw_free|close'
fuser -v /dev/snd/*
```

---

## Success criteria for this phase

One witness row with:

- ≥20 pointer samples
- IRQ before/after delta
- Class A/B/C assigned
- Optional: `hw_params` sysfs dump while hung

Then decide whether next trace targets IRQ delivery, SDW stream, or ALSA pointer update — **not** firmware reload.

---

## References

- First witness: [w2b-stream-hang-witness-20260712.md](w2b-stream-hang-witness-20260712.md)
- Script: [../../resolution/scripts/witness-stream-hang.sh](../../resolution/scripts/witness-stream-hang.sh)
