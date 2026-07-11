# Resolution tracker — edge confidence log

English (canonical). Framework v2: **exploration first**, consolidate last.

Machine state: [edges/state.json](edges/state.json) · Rules: [EDGE-FRAMEWORK.md](EDGE-FRAMEWORK.md)

**Last updated:** 2026-07-11

---

## Phase

| Field | Value |
|-------|-------|
| **Current phase** | `exploration` → **C01 confirmatory_cause** |
| **Queue** | C01 only — E07/E08 deprioritized (L4 closed) |
| **Next run** | **C01 parallel:** maintainer handoff + falsification-only (no E08) |

---

## Edge execution (PASS / FAIL / BLOCKED)

| Edge | Domain | Execution | Conf. | Notes |
|------|--------|-----------|-------|-------|
| **E04** | manager | **FAIL** | 0.35 | L2 CLOSED — RT721 ATTACHED, ALSA fail |
| **E07** | pci_probe | **FAIL** | 0.75 | **L4 CLOSED** — C02 KILLED RUN-09 |
| **E09** | runtime_pm | **BLOCKED** | 0.40 | I01 closed — usage=0 |

Inspectors: [observability/README.md](observability/README.md) · Evidence: [evidence/facts.yaml](evidence/facts.yaml)

| ID | Family | Status | Updates |
|----|--------|--------|---------|
| I01 | Snapshot | **CLOSED** | F004, F005 |
| I02 | Timeline | **OPEN** | O_IOMMU |

**Do not repeat PROMISING edges** while queue has NEW entries.

---

## Confidence model (dynamic)

| Evidence | Confidence |
|----------|------------|
| PASS once (S1–S4) | 0.60 |
| + research-coherent | 0.75 |
| + unlocks question | 0.85 → research gate |
| + consolidation each | +0.05 (cap 0.95) |
| ×3 consolidation | → **STABLE** |

---

## Exploration log

| Run | Edge | Result | Conf. | Status after | Next |
|-----|------|--------|-------|--------------|------|
| 2026-07-12-09 | E07 | FAIL / **C02 KILLED** | 0.75 | L4↓ | C01 |
| 2026-07-11-08 | E07 | FAIL partial | — | C02 conv | re-run |
| 2026-07-11-06 | E04 | FAIL | 0.35 | L2↓ | E09 retest |
| 2026-07-11-05 | S2 gate | VALID W2 | — | — | E04 |
| 2026-07-11-04 | E08 | PARTIAL | 0.40 | NEW | E04 |
| 2026-07-11-03 | E07 | PARTIAL | 0.40 | NEW | E08 |
| 2026-07-11-02 | E09 | PARTIAL | 0.40 | NEW | E07 |

---

## Consolidation sprint (later)

| Edge | Run 1 | Run 2 | Run 3 | STABLE? |
|------|-------|-------|-------|---------|
| — | — | — | — | — |

---

## Saturation (zero-K ×3)

| Edge | Zero-K streak | Saturated? |
|------|---------------|------------|
| E09 | 0 | no |
| E07 | 0 | **saturated** (informative) |
| E08 | 0 | no |

---

## Report archive

### RUN-2026-07-12-09 — E07 confirmatory (C02 **KILLED**)

- Witness W2 ✅ · R07 ok ✅ · G3 snap ✅ · G4 **RELEVANT_UNCHANGED** ✅
- Edge FAIL (ALSA) · **Campaign C02 KILLED** · Knowledge SUCCESS
- Diff: `runtime_pm` unchanged · PMCSR D0 · PCI_STATUS `0x0006` · iommu=0
- **I010** invariant · **RF004** negative · **L4 CLOSED**
- Do **not** repeat E07/E08 without new evidence

### RUN-2026-07-11-08 — E07 (C02 converging)

- S2 W2 ✅ · R07 executed ✅ · ALSA **fail** (recovery)
- R07 diff **NOT_CAPTURED** — `PMCSR=0x0000 D0` unquoted in source (`D0: orden no encontrada`)
- I02: **no IO_PAGE_FAULT** → **F013** added; H_DMA → 0.15
- **Do not repeat** until diff fix; one **confirmatory** re-run for **C02 closure** (4 gates), not audio PASS

```bash
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E07 --from-s2
# Expect: Edge FAIL + Campaign Result: C02 KILLED + G1–G4 pass + diff=RELEVANT_UNCHANGED
```

---

Paste `=== RESOLUTION EDGE REPORT ===` blocks below.

---

## Framework v2.1 — witness gate (2026-07-11)

**Insight:** E09/E07/E08 measured `S? ──R──► S?` because S2 was not certified before recovery.

| Change | Detail |
|--------|--------|
| Witness Quality | W0–W4 oracle; min **W2** to run recovery |
| Edge result | **NOT_EXECUTABLE** when witness INVALID |
| Priority | `s2-reproduce.sh` **before** E04 |
| Prior runs | E09/E07/E08 marked `witness_ambiguous` |

Doc: [WITNESS-QUALITY.md](WITNESS-QUALITY.md)

```bash
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
# then, with VALID witness:
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E04
```

---

```bash
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E04
```

**Next:** E09 retest (done RUN-07 → BLOCKED)

### I01 — 2026-07-11 (S2, post-E09 BLOCKED)

```bash
sudo ~/snd_repair/resolution/scripts/inspectors/I01-runtime-pm-blockers.sh
```

| Field | Value |
|-------|-------|
| `runtime_status` | **active** |
| `runtime_usage` | **0** ← not a PCI refcnt block |
| `runtime_suspended_time` | **0** (never runtime-suspended this boot) |
| `autosuspend_delay_ms` | 2000 |
| ALSA plughw | **FAIL** (S2) |
| Holders | **wireplumber** → `pcmC1D2p`, `controlC0/C1` |
| Kernel | `stat1=0x4` `intx_status=0` resume=2 (W3); AMD-Vi IO_PAGE_FAULT |

**Interpretation:** E09 BLOCKED is **not** “usage count on PCI sysfs”. Driver stays **active** with `runtime_usage=0` — internal state or autosuspend path dead after system resume. Wireplumber holds PCM but does not bump PCI `runtime_usage`. R09 `stop_pipewire` may be insufficient if wireplumber respawns or PCM stays open.

**I01 CLOSED:** `runtime_usage=0` — hypothesis "PCI refcnt blocks runtime PM" **discarded**. Driver stays `active` internally.

**I02 OPEN:** `AMD-Vi IO_PAGE_FAULT` on same PCI during resume — **not bonus**; correlate with PHASE10 `stat1=0x4 intx_status=0`.

```bash
# S0 (tras reboot) o S2:
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh since-last-resume
```

Then E07 (+ I02 again):

```bash
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E07 --from-s2
sudo ~/snd_repair/resolution/scripts/inspectors/I02-iommu-faults.sh
```

**Evidence:** [facts.yaml](evidence/facts.yaml) (volatile) · [invariants.yaml](evidence/invariants.yaml) (stable) · Campaigns: `campaign-status.sh`

---

| Field | Value |
|-------|-------|
| Witness | VALID W2 |
| R09 D1 | **active** 45s — no `runtime_suspend` |
| Result | **BLOCKED** |
| ALSA | fail (domain never executed) |

Driver holds PCI usage in S2. Run **I01** before abandoning E09:

```bash
sudo ~/snd_repair/resolution/scripts/inspectors/I01-runtime-pm-blockers.sh
```

**Next edge:** E07 (PCI domain — does not replace E09)

```bash
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E07 --from-s2
```

### RUN-2026-07-11-06 — E04 (first informative recovery)

`edge-cycle.sh E04 --from-s2` · witness **VALID W2**

| Field | Value |
|-------|-------|
| ALSA Verdict | **fail** → **FAIL** |
| R04 M1 | ok — platform unbound |
| R04 M2 | bound — platform back, no manager printk |
| R04 M3 | **attached** — RT721 enumerated |
| Observations | S1–S3 pass, S4 fail |

**Interpretation (Caso B):** Manager remove→probe **insufficient for S2→S3**. RT721 ATTACHED but ALSA fail → lost state is **not exclusively manager**. **L2 domain CLOSED.**

**Hypothesis update:**
- Before: `manager resume ≠ probe`
- After: `probe == enumerates` · `probe != audio usable`

See [RECOVERY-DOMAINS.md](RECOVERY-DOMAINS.md)

**Next:** E09 retest (RUN-07)

### RUN-2026-07-11-05 — S2 witness gate

- `s2-reproduce.sh` attempt 1: **VALID W2**
- ALSA `plughw:1,2` **fail** post-resume (symptom S2 — target state)
- Userspace `unknown` under sudo (ALSA authoritative; dummy trap avoided)
- Kernel W3 not latched (`handler_since_pm` / STAT1 printk optional)
- **Next:** **E04** — manager platform rebind with certified S2

```bash
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E04
```

## Runs

### RUN-2026-07-11-04 — E08

**Cycle 1 (interrupted):** R08 remove+rescan OK; crash `wait_fw_settle` — fixed (`source _lib.sh`).

**Cycle 2 (witness-only):**

```
Phase:             exploration
Edge:              E08
Recovery:          R08
Result:            PARTIAL
Status:            new
Confidence:        0.4 (dynamic)
Signature:         4/4 (S1=pass S2=pass S3=pass S4=pass S5=skip)
Next Candidate:    explore E04 (R04)
```

- S2 **no confirmado** en suspend#1 del ciclo completo (no reprodujo -110)
- Witness post-R08: **4/4** con `wait_fw_settle` 12s — audio OK tras re-enumeración
- **Conclusión:** R08 no demuestra S2→S3 — **witness_ambiguous** (v2.1 gate)
- **Next:** **s2-reproduce.sh** — not E04 until VALID witness

### RUN-2026-07-11-03 — E07

- Report: **PARTIAL** 3/4 · script dijo `bind failed` (timeout `pci_write`)
- dmesg: reprobe TAS2783 **sí** ocurrió — bind lento, no fallo real
- S4 fail: FW no lista tras reset (falta settle)
- **Fix aplicado:** `pci_reset_acp`, `wait_fw_settle` 12s, S2 por journal
- **Next:** E08

### RUN-2026-07-11-02 — E09 (terminal)

- `runtime_status=active` todo el ciclo — **runtime_suspend no ejecutado**
- Step 3: falso positivo "audio OK" (corregido → `journal_s2_witness`)
- Signature **3/4** · conf 0.40
- **Conclusión:** hipótesis E09 **no probada** vía sysfs userspace

### RUN-2026-07-11-02 — E09 (journal)

- **S1 suspend:** 20:04 → resume → RT721 `wait_init_timeout` / **-110** (classic S2)
- **R09:** runtime PM cycle ejecutado; segundo suspend ~20:05 (witness S5)
- **Post:** tarjeta ALSA presente; RT721 responde en journal (20:05:30) pero **TAS2783 :8** `fw download wait timeout` → `speaker-test` **EINVAL**
- **Resultado:** **PARTIAL** — no Recovery Signature completa (S4/S5 fail)
- **Confidence:** 0.40 · status **NEW** (no PROMISING)
- **Inferencia:** runtime PM solo **no** basta; posible mejora parcial vs -110 puro
- **Next:** **E07** — PCI unbind+bind (probe replay)

```bash
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E07
```

### RUN-2026-07-11-01 — preflight (S0)

- State: **S0**
- `preflight.sh` 8/8 OK
- Fixes: R04 platform manager; PX13 discovery paths
- **Next:** `sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E09` (exploration — one shot, then E07)
