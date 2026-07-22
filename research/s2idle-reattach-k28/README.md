# Research track — s2idle SDW re-attach fail on k28

**Branch:** `research/s2idle-sdw-reattach-k28`  
**Host:** colosal3 · PX13 HN7306EAC · kernel `7.0.0-28-generic`  
**Started:** 2026-07-19  
**Constraint:** no live PCI unbind/bind (hard freeze 2026-07-19). Recover with **cold power** only.

English (canonical). Lab history lives on `resolution/bruteforce` / `origin/research/suspend-lifecycle`; this track is the **product-era** reopen after overlay install on k28.

---

## Observed NOW (product overlay)

| Condition | SDW `:8`/`:b`/`rt721` | Speakers |
|-----------|------------------------|----------|
| Cold / clean boot | **Attached** | PASS (`speaker-test` OK) |
| After **one** s2idle | **UNATTACHED** | FAIL (`-110` resume, then FW timeout on hw_params) |
| Soft `reboot` while UNATTACHED | Often still broken until next clean power path | — |
| Cold power ≥10 s | Attached again | PASS |

Overlay markers **0001** + **0002** present under `updates/snd_repair/` on the failing boots. So “module not installed” is **ruled out**.

Userspace Soft-A (`default-profile=off`) is **ruled out** for this symptom (Speaker sink stays selected).

---

## What worked “before” (lab)

| Era | Evidence | Note |
|-----|----------|------|
| k27 + in-tree 0002 | VALIDATION matrix ✔ S2×3 (Jul 2026 product claim) | Same kick helper in `.ko` |
| Lab KPI-U 2026-07-12 | `research/…/kpi-u-s2x3-pass` on bruteforce | Broader stack (UCM + PW path + traces) |
| Q3 witness 2026-07-12 | `STAT1=0x4` after reset but **no** `irq_handler` / `handle_status` | Kick-if-pending was the intended fix |
| Phase 6 run 0013 | `ACP_EXTERNAL_INTR_STAT = 0x0` after enable/D0 | Kick-if-pending is a **no-op** |

Copies of key notes in this folder:

- [q3-sdw-reattach-witness-20260712.md](q3-sdw-reattach-k28/q3-sdw-reattach-witness-20260712.md) (path below)
- [phase6-KNOWN-FACTS.md](phase6-KNOWN-FACTS.md)

---

## Two distinct bugs (do not mix)

| | **Case A** (W8 / patch 0001) | **Case B** (this track) |
|--|------------------------------|-------------------------|
| Bus | slaves **Attached** | slaves **UNATTACHED** |
| FW | download completes | never starts / wait timeout |
| PCM | runs, silent | rejected (`-22`) |
| Root | early `fw_reinit` → mute DSP | AMD SDW resume / re-enum |
| Fix surface | `tas2783` `hw_params` | `soundwire-amd` (+ ACP) |

**Case B witnesses only** (not root): `fw download wait timeout in hw_params`, `error playback without fw download`, `trf … failed:-5 write addr 8608`, ASoC `-22`. Those fire because the codec is unreachable.

**Do not** iterate TAS2783 / 0001 while Case B is open.

---

## Causal chain (Case B — current best)

```text
s2idle resume
  → amd_resume_runtime() … manager_reset … D0  (ret=0)
  → amd_sdw_kick_irq_if_pending()
        │
        ├─ 0002: if STAT & mask != 0 → schedule_work(irq_thread)
        ├─ 0003: always ping + schedule_work(amd_sdw_work) + log kick
        └─ observed 2026-07-19: kick runs with stat=0 pend=0 sc*=0 — still FAIL
  → no UNATTACHED→ATTACHED / no completion
  → slave PM wait_init → -110 → stuck UNATTACHED
  → hw_params → fw download wait timeout (witness only)
```

**Forbidden “fix”:** `PX13_AFTER_SUSPEND=1` PCI reset — freezes machine with overlay loaded.

---

## Hypotheses (ranked)

| ID | Hypothesis | Why plausible | Next binary test |
|----|------------|---------------|------------------|
| **H1** | On k28 FAIL, `STAT==0` at kick site → 0002 never schedules work | Phase 6 FACT STAT=0 | **CONFIRMED** 2026-07-19 (`stat=0x0 pend=0x0 sc07=0x0 sc811=0x0`) |
| **H2** | `STAT!=0` but work drained / IRQ masked | Q3 STAT=0x4 w/o handler | Deferred (FAIL path has STAT=0) |
| **H3** | k27 vs k28 system-sleep / ACP timing | Product S2×3 was on k27+lab | **E2** GRUB menu contrast |
| **H4** | Unconditional / delayed kick enough | 0003 = unconditional ping+work | **REJECTED as sole fix** — 0003 ran, still UNATTACHED |
| **H5** | Missing ACP / bus bring-up **before** ping (clock, enable, reset settle) | Phase 6: software kick ret=0, STAT stays 0; ping sees dead bus | Instrument ping `status[]` + ACP regs around D0 |
| **H6** | `manager_reset` clears attach; re-enum never completes | [LINK-REENUMERATION-FAILURE.md](LINK-REENUMERATION-FAILURE.md) | Trace `handle_status` / completions ≤100 ms post-kick |
| **H7** | **Race:** 0003 kick is correct action but **too early** (managers / ACP not ready) — same class as W8, one layer down | Kick fires, `stat/sc*=0`, still UNATTACHED; W8 never reached | **0003b:** delayed re-ping+work (e.g. 20–50 ms) *or* second kick after `pm_runtime`/`resume` settles; measure Attached rate |

H1 done. Synchronous 0003 alone insufficient. Prefer binary **H7** (delayed kick) before deep ACP archaeology; still **no TAS edits**. Case A stays product-isolated for upstream.

---

## Experiment plan (safe)

### E0 — Baseline (no new code)

Already done 2026-07-19:

1. Cold boot → Attached + speaker PASS  
2. One `systemctl suspend` → UNATTACHED + `-110`  
3. Soft reboot → still fragile; cold power restores Attached  

### E1 — STAT at kick — **DONE** 2026-07-19

Overlay with **0003** installed (`installed_at=2026-07-19T11:12:15+02:00`). One s2idle:

```text
snd_repair resume enum kick: inst=1 stat=0x0 pend=0x0 sc07=0x0 sc811=0x0
rt721 / tas2783: initialization timed out / resume -110
→ UNATTACHED ×3
→ later: fw download wait timeout in hw_params (witness storm)
```

| Result | Conclusion |
|--------|------------|
| FAIL + `pending=0` | H1 confirmed |
| Kick ran (ping+work) | H4/0003 alone **not** enough → bus still dead at ping time |

### E2 — k27 contrast (GRUB menu)

Boot `7.0.0-27-generic` (in-tree 0002). Same one-S2 protocol. Cold power first.

| Result | Conclusion |
|--------|------------|
| k27 PASS, k28 FAIL | ABI/timing regression → bisect ACP/SDW deltas |
| both FAIL | Product “S2×3 ✔” was lab/conditions-specific |

### E3 — Ping / attach observation (no TAS changes)

After cold power + one S2, log whether `amd_sdw_read_and_process_ping_status` returns all-UNATTACHED and whether any `ATTACHED`/`completion` appears in ≤100 ms (reuse phase-6 style traces if needed). Binary: **dead bus at ping** vs **ping OK but handle_status lost**.

### E4 — Delayed kick (H7) — **PASS** 2026-07-19

Cold/clean boot with 0003b → one s2idle:

```text
snd_repair resume enum kick:         inst=1 stat=0x0 pend=0x0 sc07=0x0 sc811=0x0
snd_repair resume enum kick delayed: inst=1 stat=0x4 pend=0x4 sc07=0x3 sc811=0x80000
→ Attached ×3
```

| Result | Conclusion |
|--------|------------|
| Immediate kick `STAT==0` | Same as E1 FAIL window — too early |
| Delayed (+40 ms) `pend=0x4` + sc\* nonzero | Latch appeared after settle |
| Attached after S2 | **H7 confirmed** — race, not wrong action |

Keep 0003b in product path. Optional: tune delay / second kick only if needed; still no TAS edits for Case B.

---

## Working rules

1. Overlay install only (`updates/snd_repair/`); keep stock intact.  
2. No `PX13_AFTER_SUSPEND` / `px13-audio-resume` / sysfs unbind.  
3. One binary question per rebuild.  
4. After UNATTACHED: **cold power**, then continue.

---

## Status

| Item | State |
|------|-------|
| Branch created | yes |
| Case A vs B delimited | yes — Case B closed by 0003b; open gap is **Case A′** (open stream) |
| 0001/0002/0003 loaded | yes (markers OK) |
| E1 / 0003 product test | **FAIL** — kick fires, slaves stay UNATTACHED |
| E4 / 0003b delayed kick | **PASS** 2026-07-19 — Attached after S2; delayed sees `pend=0x4` |
| E4b / S2×3 | **PASS** 2026-07-19 — three cycles, same kick→delayed contrast, Attached ×3 |
| Overnight S2 2026-07-21→22 | **Case B PASS**, audio mute — [CASE-A-OPEN-STREAM-MUTE-20260722.md](CASE-A-OPEN-STREAM-MUTE-20260722.md) |
| Proposed fix | **[PROPOSED-0001b-deferred-fw-reinit.md](PROPOSED-0001b-deferred-fw-reinit.md)** — **implemented** (staged) |
| Next | `sudo ./scripts/snd-repair install-modules` + reboot; V1 Firefox-across-S2 |

```bash
# After cold power ≥10s (required while UNATTACHED):
./scripts/snd-repair status   # expect 0001/0002/0003 OK + Attached
# E2: GRUB → 7.0.0-27-generic → one S2 → Attached?
# E3: capture kick line + attach/completion window ≤100ms
```
