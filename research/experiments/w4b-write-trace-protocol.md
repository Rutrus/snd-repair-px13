# W4b / W4c / W5 — causal write trace protocol (2026-07-13)

English (canonical). Follows W4 lifecycle conclusion: **calls are identical; suspect write effect**.

---

## Strategy shift (post-W4)

| Old goal | New goal |
|----------|----------|
| Find missing driver call | Find missing or differing **write** |
| Blind vendor readback | **Ordered write trace** with phase + caller |
| Generic DAPM fix | Evidence-based W4-fix |

W4 proved: lifecycle, POST_PMU, PDE23/PPU21 readback all match PASS vs FAIL.
Bug class: **write happens but does not produce same chip state** (hot-reset path).

---

## W4b — phased write trace

Build:

```bash
sudo ./scripts/build-w4b-write-trace.sh
sudo reboot
```

Module param: `w4b_write_trace=1` (default on).

Log format:

```text
W4b ctx=write seq=N uid=8 phase=INIT_SEQ fn=tas2783_w4b_init_seq kind=regmap reg=0x00800418 val=0x0 ret=0
```

Phases:

| Phase | Set in |
|-------|--------|
| `BOOT` | `tas_io_init` entry |
| `FW_DL` | `tas2783_fw_ready` |
| `INIT_SEQ` | `init_seq` / `sdca_regmap_write_init` |
| `CALIB` | `tas2783_update_calibdata` |
| `RESUME` | `fw_reinit`, `update_status`, `resume` |
| `SUSPEND` | `system_suspend` |
| `RUNTIME` | `hw_params`, `port_prep`, PDE off |
| `DAPM` | `fu21_event`, `fu23_event` |
| `W5_MANUAL` | debugfs trigger |

Instrumented write paths:

- Every `regmap_write` (via wrapper)
- `init_seq` loop (each register, not bulk blind)
- `regmap_bulk_write` (calibration)
- `regmap_update_bits` (clear latch)
- `sdw_write_no_pm` (DAPM mute, port_prep)
- `sdw_nwrite_no_pm` (FW chunks — logged as `kind=nwrite reg=addr val=len`)

**Gap:** internal writes inside `sdca_regmap_write_init()` still opaque — bracket log only.

---

## W4c — capture and diff

### Cold PASS

```bash
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
sudo ./scripts/w4b-write-trace-capture.sh --label pass --window playback
```

### Post-S2 FAIL

```bash
systemctl suspend && sleep 20
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
sudo ./scripts/w4b-write-trace-capture.sh --label fail-s2 --window playback
```

### Diff

```bash
./scripts/w4-write-trace-diff.sh validation/w4b-write-pass-* validation/w4b-write-fail-s2-*
./scripts/w4-write-trace-diff.sh --uid 8 pass-dir fail-dir
```

Look for:

1. **Missing line** in FAIL (write A,B,C vs A,B,D)
2. **Same reg, different val** at same phase
3. **Extra write** in FAIL only (post-resume pollution)

Windows: `--window boot|resume|playback|all`

---

## W5 — double `fw_reinit` experiment

Cheap discriminator for resume-path vs hot-reset state.

```bash
# After S2 + silent speaker-test (no second suspend):
sudo ./scripts/w5-double-fw-reinit-test.sh
```

Triggers via debugfs:

```bash
echo 1 | sudo tee /sys/kernel/debug/tas2783/uid8
echo 1 | sudo tee /sys/kernel/debug/tas2783/uid11
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
```

| Outcome | Interpretation |
|---------|----------------|
| **Audio returns** | Resume ordering / stale state before first playback — fix in W2 path timing |
| **Still silent** | Hot reset + init_seq insufficient — need TI-specific warm-boot sequence |

---

## Hot-reset hypothesis (leading)

```text
cold boot:  ROM → bootloader → FW → init_seq → OK
resume:     partial reset → FW → init_seq → KO (same writes, different effect)
```

W4b/W4c should show whether **writes differ** or **writes match but chip diverges** (→ DSP/mailbox probe next).

---

## References

- [w4-tas2783-trace-protocol.md](w4-tas2783-trace-protocol.md)
- [tas2783-probe-vs-fw-reinit-w4-plan-20260713.md](tas2783-probe-vs-fw-reinit-w4-plan-20260713.md)
