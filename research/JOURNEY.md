# Investigation journey — PX13 suspend/resume (canonical)

English (canonical). Single thread from **no audio** to **resolution criteria** for the remaining blocker.

**Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`  
**Branch:** `research/suspend-lifecycle`  
**Last updated:** 2026-07-11 (Phase 8 frozen · resolution lab opened)

---

## Where we are now

| Stage | Status | Question answered |
|-------|--------|-------------------|
| Boot / stereo | **Resolved** | Can both TAS2783 amps play on cold boot? **Yes** |
| Suspend/resume (kernel) | **Delimited** | IRQ delivery: STAT pending, handler missing — downstream OK if worker runs |
| Phase 7 | **Frozen** | 0005–0007 complete — [phase-7/INDEX.md](phase-7/INDEX.md) |
| Phase 8 | **Frozen** | IRQ delivery delimited — [frozen/upstream-proof/](frozen/upstream-proof/) |
| Resolution lab | **Active** | Transition discovery S2→S3 — [../resolution/STATE-GRAPH.md](../resolution/STATE-GRAPH.md) |
| Userspace (PipeWire) | **Secondary** | Not kernel root cause |

**Kernel witness (FAIL-1 vanilla):** RT721 `-110`, no `completion`, no `irq_handler_enter`.

**Kernel witness (0007 correlate):** `STAT&mask=0x4` @ +50 ms + zero handler same boot — [0007-run-correlate-d50.md](phase-7/experiments/0007-run-correlate-d50.md).

**Kernel witness (0006a intervention):** full enumeration + RT721 `ret=0` — experiment only, not a fix.

**Upstream draft:** [phase-6/UPSTREAM-REPORT-DRAFT.md](phase-6/UPSTREAM-REPORT-DRAFT.md) — **submittable**.

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
Phase 7  Controlled experiments — delivery boundary closed (0007)
    ↓
Phase 8  ACP platform IRQ path — delimited (frozen)
    ↓
resolution/  Engineering — workarounds, recovery, mutations
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

## Phase 7 — Experiments (**frozen**)

**Goal:** *Where does enumeration fail to start?* — **answered.**

| Doc | Role |
|-----|------|
| [phase-7/INDEX.md](phase-7/INDEX.md) | Status table (all closed) |
| [phase-7/experiments/0007-run-correlate-d50.md](phase-7/experiments/0007-run-correlate-d50.md) | Delivery boundary closed |
| [phase-7/experiments/0006a-run-p7-d50.md](phase-7/experiments/0006a-run-p7-d50.md) | Downstream sufficiency |

### Experiment log

| Id | Result |
|----|--------|
| **0005** delay-after-D0 | **Negative** — STAT 0→`0x4`; not a fix |
| **0006b** STAT decode | **Closed** — Case 1 @ +50 ms |
| **0006a** manual `schedule_work` | **Closed** — downstream OK if worker runs |
| **0007** IRQ correlate | **Closed** — STAT pending + no handler, one build |

**No further Phase 7 experiments** unless new evidence contradicts the boundary.

---

## Phase 8 — ACP IRQ path (active)

**Goal:** *Where between `STAT1` pending and `acp63_irq_handler()` does resume diverge from boot?*

| Doc | Role |
|-----|------|
| [phase-8/INDEX.md](phase-8/INDEX.md) | **8.1–8.3** mini-objectives, out-of-scope, roadmap |
| [phase-8/ACP-IRQ-FLOW.md](phase-8/ACP-IRQ-FLOW.md) | Top-down IRQ diagram (8.3, fill from code) |

### Mini-objectives

| Id | Question |
|----|----------|
| **8.1** | CPU/handler never runs vs IRQ lost before Linux? (`/proc/interrupts`, handler counter) |
| **8.2** | Boot vs resume diff in `pci-ps.c` / `ps-common.c` only |
| **8.3** | Document intended ACP70 IRQ flow top-down |

**Parallel:** upstream outreach with [UPSTREAM-REPORT-DRAFT.md](phase-6/UPSTREAM-REPORT-DRAFT.md) — not a bug report yet.

**Do not repeat:** Phase 7 delays, manual schedule, STAT sweeps.

---

## Phase 7 — archived reproduce (0006a)

```bash
./scripts/build-phase7.sh --experiment validate-manager-mask --delay 50
./scripts/phase7-sweep-pre.sh 50 && sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes p7-0006a-d50
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
```

**Experiment switch** (e.g. `delay-after-d0` → `stat-decode`):

```bash
./scripts/reset-phase6-amd-manager.sh    # vanilla amd_manager + pci-ps
rm -f linux-source-7.0.0/.snd-repair-phase6-*
./scripts/build-phase7.sh --experiment validate-manager-mask --delay 50
```

---

## Resolution lab (active — transition discovery)

Research is **frozen**. [`../resolution/`](../resolution/) is a **hypothesis generator** — re-opens research only when a stable S2→S3 edge is found.

**Unit of work:** state **transition**, not experiment.  
**Prioritize:** E09 to **Stable Edge 5/5** before switching.  
**Gate:** research re-opens only on Stable Edge — [../resolution/EDGE-FRAMEWORK.md](../resolution/EDGE-FRAMEWORK.md).

See [../resolution/STATE-GRAPH.md](../resolution/STATE-GRAPH.md) · [../resolution/TRACKER.md](../resolution/TRACKER.md).

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

---

# Investigation summary

Maintainer-oriented narrative. **Facts** vs **inferences** vs **open questions** are separated throughout. Full upstream draft: [phase-6/UPSTREAM-REPORT-DRAFT.md](phase-6/UPSTREAM-REPORT-DRAFT.md).

## Initial symptom

After s2idle resume on the ASUS ProArt PX13 (AMD ACP70 + SoundWire), internal audio intermittently failed. The visible symptom was RT721 timing out (`-ETIMEDOUT`) and userspace often ending up with Dummy Output.

At this point, the failure location was unknown.

---

## Progressive narrowing

The investigation deliberately reduced the search space one layer at a time.

### Phase 1–3

The failure was classified into distinct witness classes. **FAIL-1** (RT721 waits, then timeouts) was reproducible and independent from other recovery paths. **FAIL-2** (early RT721 exit) was kept separate. This avoided mixing multiple failure modes.

### Phase 4–5

The downstream audio stack was progressively excluded:

- TAS2783 firmware is not the first failure.
- RT721 timeout is downstream.
- PipeWire recovery scripts do not explain the kernel witness path.
- SoundWire bus logic after enumeration is not the origin.

Focus moved exclusively to AMD ACP resume.

### Phase 6

Instrumentation moved into the ACP resume path. Repeated clean-boot FAIL-1 runs (e.g. run **0015**) showed:

```text
manager_reset
    ↓
irq_enabled
    ↓
(no IRQ activity in wait window)
    ↓
no ATTACHED
    ↓
RT721 timeout
```

The first observable gap was localized between interrupt enable and the beginning of SoundWire re-enumeration. The software resume sequence itself completed successfully (`ret=0` through D0).

### Phase 7 — controlled experiments

The investigation switched from observation to falsification.

**0005 (delay after D0):** `post_D0` STAT&mask = 0; at +50 ms STAT(instance=1)&mask = `0x4`. The interrupt status evolves after resume. However, no handler ran and enumeration did not start. **Inference:** the earlier “no hardware event” reading was refined — the manager interrupt becomes pending after a delay.

**0006b (STAT decode):** manager instance = 1, manager mask = `0x4`, register = `ACP_EXTERNAL_INTR_STAT1` / `ACP_SDW1_STAT`. Removed STAT0 vs STAT1 ambiguity.

**0007 (0007 correlate):** same resume cycle — manager `STAT&mask=0x4` @ +51 ms while **zero** `irq_handler_enter` (`resume≥1`). Boot path: same `STAT1=0x4` → handler → HANDLED. **Delivery boundary closed.**

**0006a (decisive for sufficiency):** the only modification was scheduling the existing IRQ worker when `stat & manager_mask`:

```c
if (stat & manager_mask)
    schedule_work(&amd_sdw_irq_thread);
```

Observed: STAT pending → manual `schedule_work` → `irq_thread` → enumeration → ATTACHED → completion → RT721 success → ALSA card created. No other code path was modified.

---

## Objective findings (demonstrated)

Directly supported by repeated experiments and logs. See [KNOWN-FACTS.md](phase-6/KNOWN-FACTS.md) for run IDs.

- AMD resume executes through manager re-init and D0 with `ret=0` on FAIL-1 (run 0015).
- On FAIL-1 (0006b / 0007), the SoundWire manager interrupt bit becomes pending at +50 ms: `STAT(instance=1) & mask(0x4) ≠ 0`.
- **`acp63_irq_handler()` does not execute** on resume (no `irq_handler_enter`, `resume≥1`) — confirmed in correlate build with shared timestamps.
- On **boot**, the same pending bit **does** invoke the handler (0007).
- Manually scheduling `amd_sdw_irq_thread` when `stat & manager_mask` **fully restores** SoundWire enumeration (0006a, run p7-0006a-d50).
- RT721 `-110` is a downstream consequence of missing `initialization_complete`.
- ALSA PCM devices are created once the worker runs (0006a).
- TAS2783, RT721 wait logic, and SoundWire enumeration after thread entry are **not** the primary failure.

---

## Supported inferences (not direct observation)

Reasonable conclusions from experiments; label as inference when talking to upstream.

- The downstream SoundWire pipeline is functional once `amd_sdw_irq_thread` runs (0006a single-variable intervention).
- The break is between **manager STAT pending** and **ACP platform IRQ delivery** (`acp63_irq_handler`), not in manager bring-up programming.
- Userspace Dummy Output after resume may occur even when kernel paths recover; it is not evidence that PipeWire caused the kernel failure (FACT 9).

---

## Not demonstrated (do not over-claim)

- The hardware never generates interrupts (STAT reads are point-in-time; +50 ms decode shows pending bit).
- MSI routing is definitely broken (plausible target, not yet traced).
- PipeWire or WirePlumber profiles are the root cause (`profile=off` after resume not demonstrated).
- The exact silicon or firmware defect.
- A natural kernel PASS on vanilla code without 0006a intervention (not observed with 0003–0007).

---

## Conclusion (delimitation complete)

```text
ACP manager — STAT(instance=1) pending @ +50 ms
        ↓
ACP / IO-APIC — interrupt not delivered to Linux on resume   ← Phase 8
        ↓
acp63_irq_handler()  [not reached]
        ↓
schedule_work(amd_sdw_irq_thread)  [downstream OK if forced — 0006a]
```

**Open question for maintainers:** what differs between boot and s2idle resume in ACP70 interrupt restore such that a pending `STAT1` condition never reaches `acp63_irq_handler()`?

See [phase-6/UPSTREAM-REPORT-DRAFT.md](phase-6/UPSTREAM-REPORT-DRAFT.md).

---

## Future work

| Tree | When |
|------|------|
| **research/** | Only if upstream maintainer requests a specific register/step |
| **resolution/** | Default — parallel tracks A–H in [../resolution/TRACKER.md](../resolution/TRACKER.md) |

**Not justified** in research unless new evidence: RT721, TAS2783, slave drivers, PipeWire, further Phase 7 sweeps.
