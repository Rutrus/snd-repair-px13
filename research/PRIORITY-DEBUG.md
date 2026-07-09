# Priority debugging — active status

**Updated:** 2026-07-09 21:30  
**Run:** `./scripts/priority-check.sh` (no root)

---

## Corrected suspend score

| Context | OK global FW | Notes |
|---------|--------------|-------|
| boot | 7/8 | |
| suspend_resume (real) | **0/8** | boot #16 excluded (false positive) |
| suspend_resume (incl. #16) | 1/9 | misleading |

---

## Boot #17 — real suspend failure (21:25)

```
PM suspend exit
  → :8, :b, rt721: PM failed -110
  → px13: pipewire SIGKILL (12s stop timeout)
  → 3× PCI reset + 30s settle + speaker-test → :8 done=0 each time
  → pipewire start failed → Dummy
```

**Conclusion:** userspace timing helps but **cannot fix** `:8 done=0` after `-110`. Kernel Serie B required.

---

## Fixes applied (this pass)

| Fix | File |
|-----|------|
| Suspend validation only after real resume | `px13-audio-fix.sh`, drop-in |
| Require `PM: suspend exit` for `--suspend` collect | `fw-validation-collect.sh` |
| systemd ordering cycle | `snd-repair-fw-validation.service` |
| `/etc/default/px13-snd-repair` | `install-px13-audio-fix.sh` |
| `priority-check.sh` | new |
| Resume: +8s ExecStartPre, 30s FW settle, 20s PW stop | drop-in + px13-audio-fix |
| PipeWire start retry ×3 | px13-audio-fix.sh |
| Boot #16 notes → `false-positive-no-suspend` | fw-matrix.csv |

---

## Test protocol (P0)

```bash
./scripts/priority-check.sh
systemctl suspend
sleep 120
./scripts/priority-check.sh
./scripts/fw-validation-run.sh suspend --notes "p0-test-N"
```

**Pass:** Speaker + `:8=OK`. **Fail:** reboot before next test.

---

## Priority order

1. **P0** Track A — kernel Serie B (`build-from-upstream.sh`)
2. **P1** Track D — `sudo install-px13-audio-fix.sh` + suspend drop-in
3. **P2** Track B — PIN4 `-22` (non-blocking)
4. **P3** Track C — video/render groups (done)
