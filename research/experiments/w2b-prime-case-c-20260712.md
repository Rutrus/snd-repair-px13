# Case C witness — W1+W2, px13 off, post-S2 audio (2026-07-12)

English (canonical). **Branch A functional PASS** (hear-first KPI).

**Boot:** same session as boot #133 · px13 disabled 13:11:06 · S2 13:11:23 → resume 13:12:01.

---

## Verdict

| Check | Result |
|-------|--------|
| px13 disabled | **PASS** — no px13 journal after 13:11:06 |
| W1 — ATTACHED post-S2 | **PASS** |
| W2 — `force_fw_reinit` | **PASS** (`:b`, `:8`) |
| Q2 — FW ladder | **PASS** `success=1 done=1` both slaves |
| `speaker-test -D hw:1,2` | **PASS — L/R alternates normally** |
| Volume | High — adjust with `alsamixer -c1` (UX, not kernel) |
| WirePlumber | **Dummy** until `restart wireplumber` → **Speaker** default |

**Split KPI:** playback Case C PASS; **full card** (capture + UCM + PW) — see [w2-full-card-recovery-kpi.md](w2-full-card-recovery-kpi.md).

**Headline:** **Branch A KPI met** — W1+W2 + px13 off restores SmartAmp post-S2.

---

## Timeline

```text
13:11:06  systemctl disable --now px13-audio-resume.service
13:11:23  systemctl suspend
13:12:01  resume — W2 force_fw_reinit → fw_ready success=1 (:b, :8)
13:13:15  speaker-test hw:1,2 — sdw_program_params ret=0, playback starts
          (user reports audible sine)
13:13:55  second SDW port program burst (~40 s — period/buffer boundary)
          user Ctrl+C — session ended
```

---

## W2 path at resume (13:12:01–04)

Same ladder as W2b boot #133: invalidate → manager_reset → 0006a → ATTACHED → W2 → io_init → nowait → fw_ready success=1.

No px13 PCI reprobe after resume.

---

## New question (post-Case C)

```text
Kernel path:     DONE (W1+W2, px13 off)
Userspace:       PipeWire still Dummy — Track D
Comfort:         volume / UCM
Production:      Case D — px13 + W2 coexistence?
```

---

## Next

1. Reproduce hang with `resolution/scripts/witness-stream-hang.sh` while blocked
2. Case D only after stream teardown understood or accepted
3. Matrix rows A/B optional for attribution

---

## References

- Matrix: [w2b-prime-matrix-protocol.md](w2b-prime-matrix-protocol.md)
- px13 confound: [px13-audio-fix-vs-w1w2.md](px13-audio-fix-vs-w1w2.md)
