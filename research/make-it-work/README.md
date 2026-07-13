# Branch A — make-it-work experiments

English (canonical). **P0 objective:** PCM2 plays after S2 without reboot.

**Canonical queue:** [MAKE-IT-WORK.md](../MAKE-IT-WORK.md)

---

## Pivot (2026-07-12)

W1 demonstrated that **ACP IRQ theory is no longer the audio bottleneck**. ATTACHED returns with 0006a; audio still fails on TAS2783 FW.

Investigation priority:

| Priority | Focus | Status |
|----------|-------|--------|
| **P0** | Force TAS2783 FW reload after resume | **W2 — active** |
| P1 | Refine fix / upstream series B | After W2 PASS |
| P2 | ACP delivery root cause (Branch B) | Frozen unless W2 fails |

---

## W2 — force firmware reinit

**Question:** If we force `tas2783_fw_reinit()` after system sleep, does PCM2 work?

**Patch:** [patches/w2-force-fw-reinit.patch](patches/w2-force-fw-reinit.patch)  
Applies on upstream series B (0001–0003). Sets `post_system_sleep` on system suspend; on first ATTACHED (`update_status` or `resume`), unconditionally calls `tas2783_fw_reinit()`.

**Result (2026-07-13):** Software path PASS (`RUNNING`, `hw_ptr`); **speakers often silent**. W5 shows a **second** reinit restores audio → investigate **when** W2 runs, not **what** it does. See [experiments/w4-w6-tas2783-double-reinit-20260714.md](../experiments/w4-w6-tas2783-double-reinit-20260714.md).

**Build (W1+W2 together):**

```bash
sudo ./scripts/build-w1-w2.sh
sudo reboot
```

Optional Q2 trace:

```bash
sudo ./scripts/build-w1-w2.sh --trace
```

**Test:**

```bash
systemctl suspend && sleep 5
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1
journalctl -k -b 0 | grep -E 'W2 ctx=tas|manual_irq_schedule|fw_ready|hw_params'
```

**Pass:** audible tone + no `fw download wait timeout` on `:8`.  
**Fail:** still silent with RUNNING/hw_ptr → W4/W5 trace stack; W6 deferred reinit sweep.

---

## W4–W6 — double reinit investigation (2026-07-13/14)

| Step | Build | Doc |
|------|-------|-----|
| W4 lifecycle | `build-w4-trace.sh` | [w4-tas2783-trace-protocol.md](../experiments/w4-tas2783-trace-protocol.md) |
| W4b + W5 manual | `build-w4b-write-trace.sh` | [w4b-write-trace-protocol.md](../experiments/w4b-write-trace-protocol.md) |
| W6 deferred | `build-w6-deferred-reinit.sh` | [w6-deferred-reinit-protocol.md](../experiments/w6-deferred-reinit-protocol.md) |

Summary: [w4-w6-tas2783-double-reinit-20260714.md](../experiments/w4-w6-tas2783-double-reinit-20260714.md)

---

## W1 witness

Partial PASS — ATTACHED yes, audio no: [experiments/w1-0006a-partial-20260712.md](../experiments/w1-0006a-partial-20260712.md)

**Root cause of W1 audio miss:** `snd-soc-tas2783-sdw` was stock (no series B); only `soundwire-amd` had 0006a.
