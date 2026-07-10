# Investigation journey — PX13 suspend/resume (canonical)

English (canonical). Single thread from **no audio** to **resolution criteria** for the remaining blocker.

**Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`  
**Branch:** `research/suspend-lifecycle`  
**Last updated:** 2026-07-11

---

## Where we are now

| Stage | Status | Question answered |
|-------|--------|-------------------|
| Boot / stereo | **Resolved** | Can both TAS2783 amps play on cold boot? **Yes** |
| Suspend/resume | **Root cause found (Phase 7)** | IRQ delivery: STAT&mask OK, handler missing — manual schedule_work fixes path |
| Active experiment | **Upstream fix design** | `pci-ps.c` / MSI — see [0006a-run-p7-d50](phase-7/experiments/0006a-run-p7-d50.md) |

**Symptom (remaining):** after `systemctl suspend` → Dummy Output, RT721 `-110`, `:8 done=0`.

---

## Journey map

```
Stage 1  brainchillz (firmware, UCM, systemd)
    ↓
Stage 2  upstream patches A/B/C (capture, FW, stereo)
    ↓
Phase 5  TAS2783 PM lifecycle trace (codec path ruled in/out)
    ↓
Phase 6  ACP70 observation — FAIL path delimited (run 0015)
    ↓
Phase 7  Controlled experiments — first behaviour change
    ↓
Fix      Minimal upstream patch + validation matrix
    ↓
Done     ≥6/6 real suspend/resume OK without reboot
```

---

## Phase 1–2 — Restore audio (closed)

**Goal:** usable stereo on cold boot.

| Step | Command / doc |
|------|----------------|
| Userspace | [docs/INSTALL.md](../docs/INSTALL.md) (brainchillz firmware + UCM) |
| Kernel tree | `./scripts/prepare-kernel-tree.sh` |
| Production modules | `./scripts/build-from-upstream.sh` |
| Verify | [docs/VERIFICATION.md](../docs/VERIFICATION.md) |

**Outcome:** Problems A (capture `-22`), B (FW timeout), C (stereo ch_map) addressed. See [docs/PROJECT-STATE.md](../docs/PROJECT-STATE.md).

---

## Phase 5 — Codec lifecycle (closed)

**Goal:** rule out TAS2783 / `tas2783-sdw.c` as root cause of resume failure.

- Index: [phase-5/INDEX.md](phase-5/INDEX.md)
- Experiment 0003 on hold; asymmetry `:8` vs `:b` points to PM resume path, not probe.

---

## Phase 6 — Observation (closed on FAIL)

**Goal:** *Where does resume break?* — answered for FAIL runs.

**Finding (run 0015):** full software kick through D0; `ACP_EXTERNAL_INTR_STAT=0` on reads; no `irq_handler_enter` in wait window; RT721 timeout is downstream.

| Doc | Role |
|-----|------|
| [phase-6/INDEX.md](phase-6/INDEX.md) | Entry point |
| [phase-6/KNOWN-FACTS.md](phase-6/KNOWN-FACTS.md) | Demonstrated vs not |
| [phase-6/PHASE-6-INVESTIGATION-STATUS.md](phase-6/PHASE-6-INVESTIGATION-STATUS.md) | Runs, exit criteria |
| [phase-6/UPSTREAM-REPORT-DRAFT.md](phase-6/UPSTREAM-REPORT-DRAFT.md) | Submit-ready draft |

### Reproduce Phase 6 trace build

```bash
./scripts/prepare-kernel-tree.sh          # once per kernel version
./scripts/build-phase6-amd-trace.sh       # applies 0003–0007, installs modules
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes run-NN
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
```

**Patches:** `research/phase-6/proposed/0003` … `0007`  
**If patch apply fails:** `./scripts/regenerate-phase6-amd-patches.sh` (regenerates 0004–0007 from `diff -u`).

---

## Phase 7 — Experiments (active)

**Goal:** *What change makes STAT / IRQ / enumeration appear?*

| Doc | Role |
|-----|------|
| [phase-7/INDEX.md](phase-7/INDEX.md) | Status table |
| [phase-7/BRINGUP-EXPERIMENTS.md](phase-7/BRINGUP-EXPERIMENTS.md) | Hypotheses A–D, rules |

### Experiment log

| Id | Result | Next |
|----|--------|------|
| **0005** delay-after-D0 | **Negative** — STAT 0→`0x4` async; not `ACP_SDW0_STAT`; no handler | Do not sweep more delays |
| **0006b** STAT decode | **Next** — observation only | See outcomes below |
| **0006a** manager mask → `schedule_work` | Pending after 0006b | IRQ delivery test |
| **0006c** force `stat==0x4` | Optional falsification | Only if a/b require |

### Reproduce Phase 7 (0006b)

```bash
./scripts/build-phase7.sh --experiment stat-decode
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes p7-0006b
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
journalctl -k -b 0 | grep 'PHASE7 ctx=amd fn=intr_decode'
```

**Experiment switch** (e.g. `delay-after-d0` → `stat-decode`):

```bash
./scripts/reset-phase6-amd-manager.sh    # vanilla amd_manager + pci-ps
rm -f linux-source-7.0.0/.snd-repair-phase6-*
./scripts/build-phase7.sh --experiment stat-decode
```

### 0006b exit branches

| Observation on FAIL | Next step |
|---------------------|-----------|
| `STAT & manager_mask` never set | 0006a likely negative; investigate CNTL programming |
| `STAT & manager_mask` set | 0006a — manual `schedule_work` |
| Wrong instance vs handler | Fix instrumentation before hardware conclusions |

---

## Resolution (not yet reached)

**Definition of done** for daily use:

1. Kernel patch (upstream-ready) that restores SoundWire enumeration after s2idle resume on PX13.
2. Validation: **≥6/6** real suspend/resume cycles with both UIDs OK in `validation/fw-matrix.csv` without reboot between cycles.
3. Document rollback: `./scripts/build-from-upstream.sh` + reboot.

**Until then:** treat any Phase 7 experiment as **falsification**, not production fix.

---

## Tooling index

| Script | When |
|--------|------|
| `prepare-kernel-tree.sh` | New kernel / fresh clone |
| `build-from-upstream.sh` | Daily stereo playback |
| `build-phase6-amd-trace.sh` | Observation / PASS hunt |
| `build-phase7.sh --experiment NAME` | One active Phase 7 patch |
| `reset-phase6-amd-manager.sh` | Experiment switch / patch recovery |
| `regenerate-phase6-amd-patches.sh` | Fix malformed 0004–0007 patches |
| `phase6-hunt.sh` | Standard run witness |

---

## Related indices

| Doc | Note |
|-----|------|
| [INVESTIGATION-INDEX.md](INVESTIGATION-INDEX.md) | Track A–D (historical) |
| [docs/PROJECT-STATE.md](../docs/PROJECT-STATE.md) | Executive project state |
| [research/README.md](README.md) | Research folder entry |

**Start here** for the full suspend/resume thread; use phase indices for depth.
