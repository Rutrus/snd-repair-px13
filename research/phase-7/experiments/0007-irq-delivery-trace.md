# Experiment 0007 — IRQ delivery trace (pci-ps)

English (canonical). **Observation only** — no behaviour change. Answers: *where does the path STAT → `acp63_irq_handler` break?*

**Prerequisite:** Phase 6 trace base (0003–0007). Patch: `0007-irq-delivery-trace.patch` on `sound/soc/amd/ps/pci-ps.c`.

**Not** Phase 6 patch `0007-phase6-resume-kick-trace` (amd_manager kick) — different file.

---

## Question (single)

> After s2idle resume, when `STAT(instance=1)&mask = 0x4` (0006b) but no enumeration, does **`acp63_irq_handler`** run? If not, is MSI/IRQ registration unchanged vs boot?

---

## Micro-probes (0007.1–0007.4)

| Id | fn log | When | Answers |
|----|--------|------|---------|
| **0007.1** | `irq_handler_enter` | Top of `acp63_irq_handler` | Handler runs at all? STAT0/1, CNTL, ENB at entry |
| **0007.2** | `request_irq` | After `devm_request_threaded_irq` | IRQ number, flags, MSI at probe |
| **0007.3** | `pm_resume_enter` / `pm_resume_done` | System resume wrapper | MSI + full IRQ block after `acp_hw_resume` |
| **0007.4** | `sdw1_irq` / `irq_handler_exit` | SDW1 branch + return | ACK path, HANDLED/NONE/WAKE_THREAD |

All lines: `PHASE7 ctx=acp fn=... resume=N` (`resume=0` boot, `resume≥1` after system sleep).

---

## Build

```bash
./scripts/build-phase7.sh --experiment irq-delivery-trace
sudo reboot
```

Installs **snd-pci-ps.ko** + **soundwire-amd.ko** (Phase 6 amd trace unchanged).

Regenerate patch: `./scripts/regenerate-phase7-0007.sh` (requires Phase 6 0005 on pci-ps).

Static check:

```bash
./scripts/check-c-file.sh sound/soc/amd/ps/pci-ps.c
```

---

## Run protocol

```bash
./scripts/phase6-hunt.sh post-reboot --notes p7-0007-boot
# optional: note boot handler lines
journalctl -k -b 0 | grep 'PHASE7 ctx=acp fn=irq_handler_enter' | head -5

systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
journalctl -k -b 0 | grep 'PHASE7 ctx=acp fn='
```

One suspend per boot (`resume_n=1`).

Optional: combine with **0006b** on amd_manager for timed STAT decode — use the combined build below.

---

## Combined run: `irq-stat-correlate` (0006b + 0007 + correlate)

Single experiment observing **both ends** of the delivery path with a **shared `t_ms`** since `manager_reset`, plus independent `/proc/interrupts` evidence.

| Layer | What it logs |
|-------|----------------|
| **amd_manager** (0006b) | `intr_decode` @ post_D0 / post_delay — `STAT&mask`, `t_since_manager_reset_ms` |
| **pci-ps** (0007) | `irq_handler_enter` / `pm_resume_done` — adds `t_mgr_ms` (exported from manager) |
| **correlate** | `cntl_write` (amd_manager), `cntl1_write` (acp70 host-wake in ps-common) |
| **host** | `phase7-irq-snapshot.sh` — IRQ 164 count pre-suspend vs post-resume |

### Build

```bash
./scripts/build-phase7.sh --experiment irq-stat-correlate --delay 50
./scripts/phase7-sweep-pre.sh 50
sudo reboot
```

Regenerate correlate patch (requires 0006b + 0007 in tree): `./scripts/regenerate-phase7-correlate.sh`

### Run protocol

```bash
./scripts/phase7-irq-snapshot.sh pre-suspend
./scripts/phase6-hunt.sh post-reboot --notes p7-correlate-d50

systemctl suspend

./scripts/phase7-irq-snapshot.sh post-resume
./scripts/phase6-hunt.sh post-suspend --save-window
journalctl -k -b 0 | grep -E 'PHASE7 ctx=(acp|amd) fn='
```

### Timeline (expected FAIL-1 @ delay 50)

```text
t=0 ms     manager_reset
t=4 ms     enable_irq / kick
t=8 ms     D0
t=50 ms    amd: intr_decode post_delay  STAT&mask=0x4
t=50–5000  pci: (no irq_handler_enter)
           /proc/interrupts IRQ164 unchanged
```

**Close delivery boundary** when all three hold in one boot. See [0007-run-resume-no-handler.md](0007-run-resume-no-handler.md).

---

## Decision tree (FAIL-1 resume window)

```text
STAT1&0x4 pending (0006b, amd_manager)
    ↓
irq_handler_enter @ resume=1 ?
    ├─ NO  → delivery before handler (MSI / mask / PCI) — compare pm_resume_done vs boot
    └─ YES → irq_handler_exit ret=?
              ├─ NONE (no SDW1 bit in handler read) → timing / already cleared
              ├─ HANDLED + sdw1_irq → handler OK; bisect schedule_work path
              └─ WAKE_THREAD only → DMA path; SDW stat separate
```

Boot contrast: same grep with `resume=0` during cold-boot enumeration — expect `irq_handler_enter` + `sdw1_irq` or `sdw0_irq`.

---

## Hypotheses (bisect order)

| Hyp | Test |
|-----|------|
| A — MSI never fires | No `irq_handler_enter` @ resume=1; `request_irq`/`pm_resume` show same irq+msi |
| B — Masked at PCI/kernel | Handler never runs; ENB/CNTL differ boot vs `pm_resume_done` |
| C — Handler runs, exits NONE | `irq_handler_enter` without `sdw1_irq`; STAT1 read in handler ≠ manager decode |
| D — Wrong registration | `request_irq` irq/msi differs after resume (unlikely) |

---

## Out of scope (next)

- **0006a.2** — unconditional `schedule_work` at post_D0 (Model A/B); after 0007 closes delivery question.
- **0008** — conditional workaround; only if 0007 proves handler never runs.

---

## Relation

| Exp | Role |
|-----|------|
| [0006b](0006b-stat-decode.md) | STAT pending @ +50 ms |
| [0006a](0006a-validate-manager-mask.md) | Manual thread sufficient |
| **0007** (this) | PCI IRQ path observation |
