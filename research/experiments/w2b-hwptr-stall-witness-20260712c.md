# hw_ptr stall witness #3 — pointers move, IRQ 160 frozen, EIO (2026-07-12)

English (canonical). Third Case C′ capture · **13:26:18** · PID **25924** · **fixed parser**.

Prior: [w2b-hwptr-stall-witness-20260712b.md](w2b-hwptr-stall-witness-20260712b.md)

---

## Verdict

| Observation | Result |
|-------------|--------|
| `wait_for_avail` block | Yes (stack) |
| **`hw_ptr` frozen (Class C)** | **No** — advances ~8.6k–9.1k per 500 ms (t=1s–11s) |
| **`appl_ptr` frozen** | **No** — advances similarly; gap appl−hw shrinks (7056 → ~1472) |
| **ACP_PCI_IRQ (160) Δ +2 s** | **0** (stuck at **286**) |
| End state | PCM **closed**; T1 **EPIPE (-32)** then **EIO (-5)** |

**Rejects** simple model: “IRQ 160 frozen ⇒ hw_ptr frozen.” Progress and this IRQ counter are **decoupled** during streaming (DMA/period may use another event path, or IRQ 160 is not the playback period line).

---

## Pointer series (valid samples)

```text
t=0ms     hw=38176  appl=45232   (appl ahead 7056)
t=500ms   hw=8752   appl=9392    (wrap — raw d_hw negative, ignore)
t=1000ms  hw=17648  appl=19168   d_hw≈8896/500ms
…
t=11000ms hw=194544 appl=196016  d_hw≈8880/500ms
t=11500ms ? — PCM closing
```

At 48 kHz, full-rate expectation ≈ **24000 frames / 500 ms**. Observed ≈ **8800 / 500 ms (~37% real-time)** or partial period cadence — **needs `delay`/`avail` series** (no wrap ambiguity).

**Process state:** blocked in `wait_for_avail` while `hw_ptr` still advanced → back-pressure / buffer accounting, not hard motor stop for entire window.

---

## IRQ

```text
ACP_PCI_IRQ total: 286 @ t+0s, 286 @ t+2s, d=0
```

Same count as boot #133 resume witness (286) — **likely cumulative since boot/resume**, not incrementing during SmartAmp playback window. Do **not** use IRQ 160 alone as period-IRQ witness; find ACP DMA / per-stream IRQ in `/proc/interrupts` next.

---

## Terminal 1 — failure mode

```text
Error de escritura: -32 (EPIPE)   # canal 0
Error de escritura: -5 (EIO)      # canal 1
xrun_recovery failed → EIO
```

Stream collapsed ~11 s into test; aligns with `?` pointers and `PCM closed` at end of script.

---

## Updated hypothesis tree

```text
START ✓ → playback progresses (hw_ptr moves)
         → userspace may still block in wait_for_avail (buffer full / pacing)
         → ACP_PCI_IRQ 160 not ticking during stream
         → eventual EIO/xrun (~10–40 s) — mechanism TBD
```

**Not** pre-START FW failure. **Not** proven “no period IRQs at all.” **Not** Class C pointer freeze for whole hang.

---

## Script / protocol updates

1. Log **`delay`** and **`avail`** each sample (recommended KPI — no ring wrap).
2. Raw `d_hw` invalid across **hw_ptr wrap** (t=500 ms artifact).
3. Grep `/proc/interrupts` for **ACP DMA** / `snd_acp` / MSI lines, not only `ACP_PCI_IRQ`.

---

## References

- Protocol: [w2b-hwptr-stall-protocol.md](w2b-hwptr-stall-protocol.md)
- Case C PASS: [w2b-prime-case-c-20260712.md](w2b-prime-case-c-20260712.md)
