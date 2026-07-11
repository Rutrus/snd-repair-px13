# Run p7-correlate-d50 — IRQ delivery boundary closed (0006b + 0007 + correlate)

English (canonical). **2026-07-11** · boot `28be3d07-8b1f-40fd-830b-854f1195b149` · notes `p7-correlate-d50`

Build: `irq-stat-correlate` · `phase7_delay_ms=50` · hunt `FAIL-1`

Saved: `validation/phase6-runs/hunt-p7-correlate-d50/kmsg-phase6-window.log`

IRQ snapshots: `validation/.state/irq-post-resume-20260711T030749.txt` (IRQ **160** this boot; pre-suspend file is prior boot IRQ 164 — see note below)

---

## Headline — delivery boundary closed in one build

Three independent witnesses align on the **same resume cycle**:

| Witness | Result |
|---------|--------|
| **amd** `intr_decode post_delay` @ t≈51 ms | `STAT1=0x4` `STAT&mask=0x4` `CNTL1=0x400004` |
| **pci** `irq_handler_enter` @ `resume≥1` | **None** in RT721 wait window (~5 s) |
| **CNTL writers** | Sequential: `acp70_host_wake → 0xc00000`, then `amd_manager → 0x400004` |

→ Break is **not** in SoundWire manager decode or mask programming. It is **after** `ACP_EXTERNAL_INTR_STAT1` pending, **before** Linux delivers IRQ **160** to `acp63_irq_handler`.

---

## Shared timeline (resume=1)

```text
t=0 ms     manager_reset
           pm_resume: cntl1_write acp70  old=0x0 new=0xc00000
           pm_resume_done  cntl1=0xc00000  t_mgr_ms=-1  (before manager_reset anchor)
t=0 ms     cntl_write amd_manager  mask=0x4  cntl_after=0x400004  t_ms=0
           intr_decode post_D0   STAT&mask=0x0
t=50 ms    delay_before_decode delay_ms=50
t=51 ms    intr_decode post_delay  STAT1=0x4  STAT&mask=0x4  CNTL1=0x400004
t=51–5000  (no irq_handler_enter resume≥1)
           wait_init_timeout  ret=-110
t=+37 s    request_irq resume=1  (PCI re-probe after FAIL — noise)
```

Boot reference (same boot, `resume=0`): many `irq_handler_enter irq=160` → `sdw1_irq stat1=0x4 ack=0x4` → `HANDLED`.

---

## CNTL1 — two writers, sequential (not a race)

| When | Who | Value |
|------|-----|-------|
| `pm_resume_done` | **acp70** host-wake (`cntl1_write`) | **0xc00000** |
| `cntl_write` t_ms=0 | **amd_manager** SDW1 mask | **0x400004** |

---

## IRQ topology (this boot)

| Field | Value |
|-------|-------|
| Linux IRQ | **160** (varies by boot; was 164 on p7-0007-boot) |
| GSI / IO-APIC | IR-IO-APIC 13-fasteoi **ACP_PCI_IRQ** |
| `msi` | **0** |
| Boot handler | Many hits `stat1=0x4` |
| Resume handler | **Zero** after `pm_resume_enter` |

---

## `/proc/interrupts` note

Post-resume snapshot (this boot):

```text
160: ... CPU31=33 ... IR-IO-APIC 13-fasteoi ACP_PCI_IRQ
```

All **33** counts are consistent with boot enumeration handlers (03:05–03:06, `resume=0`). No `irq_handler_enter` with `resume≥1` after 03:07:31.

Pre-suspend file `irq-pre-suspend-20260711T023241.txt` captured IRQ **164** from the **previous** boot (before correlate reboot). For a same-boot delta, re-run with `phase7-irq-snapshot.sh pre-suspend` immediately before suspend on the correlate boot. Journal + hunt already suffice to close delivery.

---

## Classification

**FAIL-1** · **S1-delayed** (Case 1): post_D0 `STAT&mask=0`; post_delay `STAT&mask=0x4`; no handler.

Matches [0006b](0006b-stat-decode.md) Case 1 and [0007-run-resume-no-handler.md](0007-run-resume-no-handler.md) resume path — now with **correlated timestamps** in one build.

---

## Boundary statement (for upstream)

```text
ACP_EXTERNAL_INTR_STAT1  (STAT1=0x4 pending @ +50 ms, CNTL1=0x400004)
        │
        ▼
ACP / IO-APIC interrupt routing & enable restoration after s2idle
        │
        ▼
Linux IRQ 160  →  acp63_irq_handler   [NOT REACHED on resume]
```

SoundWire enumeration logic (`schedule_work` / `amd_sdw_irq_thread`) is downstream; [0006a](0006a-validate-manager-mask.md) showed manual schedule is sufficient when the thread runs.

---

## Next steps (research)

1. **Phase 8** — ACP70 interrupt restore after s2idle (see [UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md)).
2. Optional: same-boot `/proc/interrupts` pre/post for cosmetic hardening.
