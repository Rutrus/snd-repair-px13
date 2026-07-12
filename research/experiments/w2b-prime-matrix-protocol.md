# W2b′ — causal matrix protocol (px13 off vs W1/W2)

English (canonical). **Branch A** clean experiment after W2b kernel witness ([w2b-q2-trace-20260712.md](w2b-q2-trace-20260712.md)).

**Question shift:**

```text
Before:  Which component is broken?
Now:     What minimal change restores audio after S2?
```

---

## Confounding variable — `px13-audio-resume.service`

If px13 runs during Cases A–C, you cannot tell whether success/failure came from W1/W2, from PCI reset, or from both.

**Rule:** Cases **A–C** require px13 **disabled** (see [px13-audio-fix-vs-w1w2.md](px13-audio-fix-vs-w1w2.md)). Case **D** only — px13 **on** — tests convivencia with the production workaround.

The unit is **not neutral**: 3 s + drop-in 8 s delay, then PCI unbind/bind + PipeWire recycle — it rewrites hardware state ~11 s after every resume.

---

## Experiment matrix

One **cold boot per row** when the kernel module stack changes. Same boot may run **multiple S2 cycles** only when the row’s modules and px13 state are unchanged.

| Case | `px13-audio-resume` | W1 (0006a) | W2 (force FW) | Primary question |
|------|---------------------|------------|---------------|------------------|
| **A** | Off | No | No | Baseline broken (stock stack) |
| **B** | Off | Yes | No | ATTACHED only — audio still dead? |
| **C** | Off | Yes | Yes | **Does W1+W2 restore KPI?** |
| **D** | On | Yes | Yes | W2 + brainchillz px13 — coexistence |

Cases A–C isolate causality. **Case C is the critical functional test — complete it before Case D.**

**Do not run Case D until Case C is decided.**

---

## Case C — immediate procedure (P0)

No new IRQ trace. **Hear first, logs second.**

```bash
sudo systemctl disable --now px13-audio-resume.service && sudo systemctl daemon-reload
systemctl is-enabled px13-audio-resume.service
systemctl list-dependencies suspend.target | grep px13 || echo "clean"

systemctl suspend
sleep 45    # 30–60 s: do not touch system; px13 would fire ~11 s if still enabled

speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1

# Only after pass/fail by ear:
journalctl -b -u px13-audio-resume.service --no-pager
journalctl -k -b 0 | grep -E 'TAS2783Q2|W2 ctx|fw download|px13-audio'
```

| Hear tone? | px13 journal | Conclusion |
|------------|--------------|------------|
| Yes | empty | **W2 works** — run A/B for attribution |
| No | empty | W2 insufficient — classify with Q2 |
| — | non-empty | Row invalid — fix disable, retry |

---

## Three mechanisms — never mix in one row

```text
(1) PM resume alone        → baseline broken (Case A)
(2) W1 → ATTACHED          (Case B)
(3) W1+W2 → force_fw_reinit on system sleep  (Case C)
(4) px13 → PCI destroy/reprobe (~partial ACP cold boot)  (Case D only)
```

px13 does not validate PM; it **avoids** it via a different path ([px13-audio-fix-vs-w1w2.md](px13-audio-fix-vs-w1w2.md)).

---

## Overwrite hypothesis (boot #133 — journal-verified)

```text
12:58:08  W2 → :8/:b success=1 done=1 hw_init=1  (PM resume path)
12:58:19  px13 starts PCI reset
12:58:23  PCI bind → update_status status=0 skip_io_init — NO W2 force_fw_reinit
12:58:38  fw download wait timeout (success=0 done=0)
```

W2 likely left the system correct; px13 reprobe entered a path **without** `post_system_sleep` / W2 reinit and broke KPI. Case C tests whether W2 alone is **functionally** sufficient.

---

## Module stack per case

| Case | Build / install |
|------|-----------------|
| A | Stock distro modules (reinstall if W1/W2 currently installed) |
| B | `sudo ./scripts/build-phase7.sh --experiment validate-manager-mask` only — **no** W2 on `snd-soc-tas2783-sdw` |
| C, D | `sudo ./scripts/build-w1-w2.sh` (add `--trace` while debugging) |

After switching stacks: **reboot** before recording the row.

---

## px13 — disable first (Cases A–C)

Detail: [px13-audio-fix-vs-w1w2.md](px13-audio-fix-vs-w1w2.md).

**Prefer `disable`** — removes `WantedBy=suspend.target` links. Use `mask` + move unit file only if the unit still starts after disable.

```bash
sudo systemctl disable --now px13-audio-resume.service
sudo systemctl daemon-reload
```

**Before suspend:**

```bash
systemctl is-enabled px13-audio-resume.service
systemctl is-active px13-audio-resume.service
systemctl list-dependencies suspend.target | grep px13 || echo "px13 not hooked"
systemctl cat px13-audio-resume.service
```

Expect: `disabled`, `inactive`, no `px13` under `suspend.target`.

**After resume (clean run):**

```bash
journalctl -b -u px13-audio-resume.service --no-pager
journalctl -b | grep px13-audio-fix || echo "no px13 intervention"
```

Empty unit journal + no `px13-audio-fix` lines → experiment not contaminated.

**If disable is insufficient:**

```bash
sudo mv /etc/systemd/system/px13-audio-resume.service{,.bak}
sudo systemctl mask px13-audio-resume.service && sudo systemctl daemon-reload
systemctl cat px13-audio-resume.service    # → /dev/null
systemctl status px13-audio-resume.service
```

**Restore (Case D or daily driver):**

```bash
sudo systemctl unmask px13-audio-resume.service 2>/dev/null || true
[[ -f /etc/systemd/system/px13-audio-resume.service.bak ]] && \
  sudo mv /etc/systemd/system/px13-audio-resume.service.bak /etc/systemd/system/px13-audio-resume.service
sudo systemctl enable px13-audio-resume.service && sudo systemctl daemon-reload
```

---

## Per-case procedure

Case C: see **Case C — immediate procedure** above (45 s wait, `speaker-test` before logs).

Other cases (after module stack reboot):

```bash
systemctl suspend && sleep 45
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1
# then logs / wpctl
```

---

## Success criteria (Case C)

**Primary (decisive):** `speaker-test -D hw:1,2` → **audible tone**, with `journalctl -b -u px13-audio-resume.service` empty.

**Secondary (explain result, not gate):**

| # | Signal | Notes |
|---|--------|-------|
| 1 | WirePlumber sink | Real device vs Dummy default |
| 2 | Kernel dmesg | No `fw download wait timeout` on `:8` after S2 |
| 3 | Q2 trace | `fw_ready exit … success=1` on PM resume path |

---

## Expected outcomes (hypothesis)

| Case | Expected ATTACHED | Expected PCM2 / tone |
|------|-------------------|----------------------|
| A | Often no / unstable | FAIL |
| B | Yes (W1) | FAIL (no FW reinit) |
| C | Yes | **PASS** if W2b kernel witness transfers to userspace |
| D | Yes after px13 reset | Unknown — px13 may clear W2 state post-resume |

W2b boot #133 already showed Case **C kernel path** PASS at 12:58:08; KPI was never tested before px13 ran at 12:58:19.

---

## Witness template (copy per row)

```markdown
## Case X — boot #NNN — YYYY-MM-DD

- px13: off|on
- modules: stock | W1 | W1+W2 (+ trace?)
- S2 time: …
- speaker-test hw:1,2: PASS|FAIL (heard tone: y/n)
- wpctl default sink: …
- fw timeout count post-S2: N
- fw_ready success=1 on :8: y/n
- notes: …
```

---

## References

- Queue: [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md)
- W2b kernel witness: [w2b-q2-trace-20260712.md](w2b-q2-trace-20260712.md)
- Q2 hypotheses: [../q2-fw-resume/HYPOTHESES.md](../q2-fw-resume/HYPOTHESES.md)
