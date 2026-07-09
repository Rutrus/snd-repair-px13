# Priority debugging — pointer

**Canonical project state:** [`../docs/PROJECT-STATE.md`](../docs/PROJECT-STATE.md)

---

## TL;DR (2026-07-09)

| | |
|---|---|
| **Works** | Cold boot stereo, `:b` 20/20, brainchillz + patches A/C, px13 hardened |
| **Fails** | Suspend/resume → `-110` → `:8 done=0` → Dummy (0/9 real) |
| **Priority** | Series B modules → 3–5 suspend cycles |
| **Hypothesis** | H1 only: PM resume does not restore left TAS2783 (`:8`) |

---

## Quick check

```bash
./scripts/priority-check.sh
```

## Next test (P0)

```bash
./scripts/reset-kernel-tree.sh          # if upstream apply failed or tree has ENZOPLAY
./scripts/build-from-upstream.sh        # A+B+C, installs tas2783 + sdw_utils
sudo reboot
# then: suspend × 3–5, ./scripts/fw-validation-run.sh suspend --notes "serie-b-N"
```

Do **not** use `install-tas2783-ko.sh` (deprecated; only built tas2783 from a dirty tree).

See [`SUDO-RUNBOOK.md`](SUDO-RUNBOOK.md).
