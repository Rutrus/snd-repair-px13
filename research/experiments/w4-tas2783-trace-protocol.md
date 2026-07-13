# W4 — TAS2783 driver trace protocol (2026-07-13)

English (canonical). **Diagnostic patch only** — not a production fix.

Follows E2: ALSA/mixer/sysfs **indistinguishable** between cold PASS and post-S2 silent FAIL.
Investigation pivots from Linux stack to **TAS2783 internal state**.

Evidence: `validation/tas2783-state-pass-cold-20260713-112648` vs
`validation/tas2783-state-fail-silent-s2-20260713-112812`.

---

## What E2 proved

| Observable layer | Cold PASS | Post-S2 FAIL |
|------------------|-----------|--------------|
| amixer / wpctl | identical | identical |
| PCM hw_ptr | advances | advances |
| SDW enumeration | OK | OK |
| W2 `force_fw_reinit` | absent | present |
| Audible speakers | yes | **no** |

**Conclusion:** lost state is **not visible from ALSA**. Target chip-private registers / init sequence.

---

## W4 patch

`research/make-it-work/patches/w4-tas2783-trace.patch` on **upstream series B + W2**.

Three module parameters:

| Param | Default | Purpose |
|-------|---------|---------|
| `w4_lifecycle_trace` | 1 | Ordered `W4 ctx=life seq=N fn=… phase=…` |
| `w4_readback_trace` | 1 | `W4 ctx=rb` — PDE23, PPU21, FU21/FU23 mute, AMP |
| `w4_sdca_trace` | 0 | Every `regmap_write`, `sdw_write`, FW `nwrite` |

Build:

```bash
sudo ./scripts/build-w4-trace.sh
sudo reboot
```

Enable full SDCA write log (verbose):

```bash
sudo ./scripts/build-w4-trace.sh --sdca-trace
sudo reboot
```

---

## Capture protocol

### A — Cold boot (speakers audible)

```bash
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
sudo ./scripts/w4-trace-capture.sh --label pass-cold-playback
```

### B — Post-S2 (speakers silent, jack OK)

```bash
systemctl suspend && sleep 20
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1
sudo ./scripts/w4-trace-capture.sh --label fail-s2-playback
```

### C — Diff

```bash
./scripts/w4-trace-diff.sh \
  validation/w4-trace-pass-cold-playback-* \
  validation/w4-trace-fail-s2-playback-*
```

Look for:

1. **Missing `fn:phase` step** in FAIL (e.g. `fu21_event:post_pmu` never fires post-S2)
2. **Readback delta** at `hw_params_out` or `io_init_out` (PDE23/PPU21 power)
3. With `--sdca-trace`: first differing `regmap_write` after `fw_reinit`

---

## Lifecycle functions traced

| fn | When |
|----|------|
| `system_suspend` | S2 entry |
| `resume` | S2 exit branches |
| `update_status` | SDW attach + W2 path |
| `fw_reinit` | W2 forced reload |
| `io_init` | reset → FW → init_seq |
| `fw_ready` | async FW download |
| `update_calib` | UEFI calibration |
| `hw_params` | PDE23 power + stream |
| `port_prep` | DPN prepare |
| `fu21_event` / `fu23_event` | DAPM POST_PMU / PRE_PMD |

---

## Expected outcomes

| Diff pattern | Likely cause |
|--------------|--------------|
| PASS has `fu21_event:post_pmu`, FAIL missing | Stale DAPM — chip reset without widget replay |
| `rb` shows PDE23/PPU21 OFF on FAIL | Analog power domain not restored |
| Same lifecycle, different `rb` values | FW OK but register values wrong post-reinit |
| FAIL skips `init_seq` phase | `hw_init` short-circuit or `sdca_regmap_write_init` path |

---

## Next step after W4 diff

**W4-fix** — minimal restore of the **first proven missing step**, not generic `dapm_sync`.

References: [tas2783-probe-vs-fw-reinit-w4-plan-20260713.md](tas2783-probe-vs-fw-reinit-w4-plan-20260713.md)
