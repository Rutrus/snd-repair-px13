# Q2 — TAS2783 firmware resume trace

English (canonical). **Q2 closed for the 2026-07-12 witness cycle.** Next: **bus re-attach (Q2.5)**.

| Doc | Role |
|-----|------|
| [CONSOLIDATION.md](CONSOLIDATION.md) | Handoff summary + upstream wording |
| [../experiments/q2-fw-trace-witness-20260712.md](../experiments/q2-fw-trace-witness-20260712.md) | **Full witness** |
| [HYPOTHESES.md](HYPOTHESES.md) | H1–H4 matrix + verdicts |
| [../tas2783-fw_dl_success-map.md](../tas2783-fw_dl_success-map.md) | Static `fw_dl_success` map |
| [../experiments/pcm-dual-path-trace-20260712.md](../experiments/pcm-dual-path-trace-20260712.md) | Q1 witness |

---

## Q2 outcome (one paragraph)

On the captured resume cycle, **no observable `tas_io_init()`** runs before `hw_params()` times out; **`request_firmware_nowait()` and `tas2783_fw_ready()` never appear** in the trace. Slaves remain **`status != ATTACHED`** after `manager_reset`; `resume: initialization timed out` occurs on **both** `:8` and `:b`. The block is **before** the async firmware ladder; **where** in the SoundWire re-attach path attach fails is **still open**.

---

## Build (upstream A+B+C + Q2 trace)

```bash
rm -f ~/linux-source-7.0.0/.snd-repair-q2-fw-trace-applied   # if patch changed
./scripts/regenerate-q2-fw-trace-patch.sh   # if anchors drift
./scripts/build-q2-fw-trace.sh
sudo reboot
```

Probes: `tas_update_status`, `tas_io_init`, `tas2783_fw_reinit`, `tas2783_fw_ready`, system suspend/resume, `tas_sdw_hw_params` wait/reinit.

---

## Protocol

```bash
./scripts/q2-fw-trace-collect.sh --label boot
systemctl suspend
sleep 5
./scripts/q2-fw-trace-collect.sh --label after-resume
sudo resolution/scripts/pcm-hwparams-trace.sh --label S2 --dual-path \
  --skip-pre-witness --probe-order pcm2,pcm0
./scripts/q2-fw-trace-collect.sh --label after-aplay
```

Archive: `validation/q2-fw-trace/<label>-*.log`

---

## Read results

```bash
journalctl -k -b 0 | grep TAS2783Q2
```

---

## Upstream wording

**Safe:** Q1 chain; “no observable firmware async start before hw_params timeout (this cycle)”; “slave did not reach ATTACHED before hw_params.”

**Avoid:** “H1 confirmed” without cycle qualifier; “skip_io_init caused failure”; “bug is in AMD manager” without re-attach localization.

Keep Phase 6–8 IRQ report **separate** unless same-boot correlation captured.
