# hw_ptr stall witness #2 — IRQ frozen, EIO xrun (2026-07-12)

English (canonical). Second Case C′ capture · **13:24:34** · PID **24883**.

**Note:** Pointer time series in this run is **invalid** (script parsed `hw_ptr:` but sysfs uses `hw_ptr      :` — fixed in script). IRQ + final status remain valid.

---

## Proven this run

| Observation | Evidence |
|-------------|----------|
| Blocked in `wait_for_avail` | stack + wchan |
| PCM `RUNNING` at capture end | status sysfs |
| `appl_ptr` ahead of `hw_ptr` | 274608 vs 271312 (delay 3296) |
| **ACP_PCI_IRQ (160) frozen +2 s** | count **286** in both IRQ snapshots |
| Userspace ended with **EIO (-5)** | `xrun_recovery` failed (terminal 1) |

---

## IRQ correlation (strongest signal so far)

```text
snapshot 1 (+0s):  IRQ 160 ACP_PCI_IRQ … 286
snapshot 2 (+2s):  IRQ 160 ACP_PCI_IRQ … 286   d_irq = 0
```

While PCM was `RUNNING` and `speaker-test` blocked in `wait_for_avail`:

- **ACP legacy IRQ did not increment** over the measured window.

This does **not** alone prove “no period interrupts ever,” but it supports **IRQ delivery / handler path not advancing playback** during the stall — aligns with Branch B territory **after** START succeeds.

Still distinguish: frozen IRQ + frozen `hw_ptr` (Class C) vs frozen IRQ + moving `hw_ptr` (driver update path). **Re-run fixed script** for pointer series.

---

## Final PCM snapshot (end of script)

```text
state: RUNNING   owner_pid: 24883
delay: 3296   avail: 4896
hw_ptr: 271312   appl_ptr: 274608
```

Buffer not full (cf. delay 7856 earlier) — stall may have started earlier; process still blocked waiting for drain.

---

## Terminal 1 outcome (after witness)

```text
Error de escritura: -5 (EIO)
falló xrun_recovery: -5
Transferencia fallida: EIO
```

Playback did not clean-finish — ALSA reported I/O error after buffer progress stopped. Not STOP/CLOSE hang; **mid-stream failure** escalating to xrun/EIO.

No matching kernel error lines in brief journal grep (may be silent xrun in driver).

---

## Script bug (fixed)

ALSA `/proc/asound/card*/pcm*/sub0/status` format:

```text
hw_ptr      : 271312
```

Old grep `^hw_ptr:` matched nothing → series showed `?`. Fixed: `[[:space:]]*:` + value after colon.

---

## Next

One more capture with fixed script during hang — expect Class C if `d_hw=0` over 12 s **and** `d_irq=0`.

---

## References

- Protocol: [w2b-hwptr-stall-protocol.md](w2b-hwptr-stall-protocol.md)
- Script: [../../resolution/scripts/witness-stream-hang.sh](../../resolution/scripts/witness-stream-hang.sh)
