# W2 witness — force_fw_reinit partial PASS (2026-07-12)

English (canonical). Branch A experiment **W2** after `build-w1-w2.sh` (0006a + upstream B + force-fw-reinit).

**Machine:** ASUS ProArt PX13 · kernel `7.0.0-27-generic` · suspend ~12:34:49 local.

---

## Verdict

| Layer | Result |
|-------|--------|
| Loaded module has 0003 + W2 | **PASS** (`srcversion` + `W2 ctx=tas` in installed `.ko.zst`) |
| W1 — ATTACHED post-S2 | **PASS** |
| W2 — `force_fw_reinit` invoked | **PASS** (`:b` uid=11, `:8` uid=8) |
| SDW `completion` | **PASS** (~1.4 s / ~2.7 s) |
| `fw_dl_success` / PCM2 hw_params | **FAIL** — wait timeout → -EINVAL |
| PipeWire Speaker sink | **FAIL** — Dummy Output only (expected consequence) |
| PCM0 RT721 (`hw:1,0`) | **PASS** — `speaker-test` OK |

**W2 answers:** forcing `tas2783_fw_reinit()` on ATTACHED **does run** after W1 reattach.

**W2 does not answer:** why async firmware never completes (`fw_ready` / `fw_dl_success`).

---

## Userspace chain (confirmed)

```text
PipeWire → open Speaker → ALSA hw:1,2
    → tas_sdw_hw_params()
    → fw download wait timeout
    → -EINVAL
    → no usable PCM
    → WirePlumber: Dummy Output only
```

Dummy Output is **not** a separate investigation target.

---

## Kernel sequence (12:34:49, post-S2)

```text
0006a manual_irq_schedule → handle_status → ATTACHED
W2 ctx=tas fn=force_fw_reinit when=update_status uid=11
W2 ctx=tas fn=force_fw_reinit when=update_status uid=8
completion (:b 1388ms, :8 2724ms)
PM suspend exit OK

~31s later (PipeWire / speaker-test on hw:1,2):
  fw download wait timeout in hw_params (:8)
```

No `tas2783_fw_ready` / `request_firmware_nowait` strings in journal (no Q2 trace on module).

---

## Decoupling achieved (W1 + W2)

```text
Before:  Resume → no ATTACHED → no io_init → no FW → no audio

After W1: Resume → ATTACHED OK (with 0006a)

After W2: ATTACHED → force_fw_reinit CALLED → FW async still broken → no audio
```

Active bottleneck: **TAS2783 async firmware completion**, not ACP/IRQ, not PipeWire.

---

## Next — W2b

1. `sudo ./scripts/build-w1-w2.sh --trace` — Q2 probes on `tas_update_status` / `tas_io_init` / `fw_ready`
2. Re-run S2; classify H1–H4 from [q2-fw-resume/HYPOTHESES.md](../q2-fw-resume/HYPOTHESES.md)
3. If `nowait ret=0` but no callback → W2c (sync FW load hack)

---

## Related

- [w1-0006a-partial-20260712.md](w1-0006a-partial-20260712.md)
- [MAKE-IT-WORK.md](../MAKE-IT-WORK.md)
