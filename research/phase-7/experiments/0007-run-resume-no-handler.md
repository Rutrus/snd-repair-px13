# Run p7-0007-boot — resume IRQ not delivered (0007 only)

English (canonical). **2026-07-11** · boot `4f10e33f-dfac-4cbc-88c8-668616f9dd49` · notes `p7-0007-boot`

Patch: [0007-irq-delivery-trace](0007-irq-delivery-trace.md) on Phase 6 base (**no** 0006b decode in this run).

Hunt: `FAIL-1` · saved `validation/phase6-runs/hunt-p7-0007-boot/kmsg-phase6-window.log`

---

## Headline

**Boot:** `STAT1=0x4` → IRQ **164** → `acp63_irq_handler` → `sdw1_irq` → ACK → HANDLED.

**Resume (FAIL-1):** full manager kick, `intr_cntl=0x400004`, `STAT=0` at Phase 6 snapshots — **zero** `irq_handler_enter` with `resume≥1` in the RT721 wait window.

The finding is **resume delivery**, not boot behaviour.

---

## IRQ topology (corrects MSI assumption)

| Field | Value |
|-------|-------|
| `request_irq` | irq=**164**, flags=**0x80** (IRQF_SHARED) |
| `msi` | **0** (legacy line, not MSI) |
| Boot handler | **Many** `sdw1_irq` on `stat1=0x4` |
| Resume handler | **None** after `pm_resume_enter` |

---

## Boot path (resume=0) — reference

```text
irq_handler_enter  stat1=0x4  cntl1=0x4
    ↓
sdw1_irq  ack=0x4
    ↓
irq_handler_exit  ret=HANDLED
```

Repeated through enumeration (02:15:33–02:18:02).

---

## Resume path (resume=1) — FAIL

```text
02:18:23  pm_resume_enter/done
          stat0=0 stat1=0  cntl1=0xc00000  (after acp_hw_resume)
    ↓
          manager_reset → kick → intr_cntl_post_enable 0x400004
    ↓
          RT721 wait_init 5.4s
    ↓
          (no irq_handler_enter resume≥1)
    ↓
          wait_init_timeout  ret=-110
```

---

## CNTL1 — two writers (not a race)

| When | Who | CNTL1 |
|------|-----|-------|
| `pm_resume_done` | **acp70** `acp_hw_resume` → host-wake enable | **0xc00000** (`ACP70_SDW_HOST_WAKE_MASK`) |
| `intr_cntl_post_enable` | **amd_manager** `amd_enable_sdw_interrupts` | **0x400004** (SDW1 mask `0x4` + host wake) |

Sequential programming, not concurrent overwrite. Next build logs **writes** explicitly (`cntl_write`).

---

## Noise after FAIL

`request_irq resume=1` at +15s / +49s = **PCI re-probe** after TAS remove/probe and `IO_PAGE_FAULT` — downstream of timeout, not cause.

---

## What this run does *not* show

- No **0006b** `post_delay` snapshot — cannot confirm `STAT1=0x4` at +50 ms in same build (known from p7-0006b-d50 / 0006a).
- No `/proc/interrupts` delta — add on next run.

---

## Next run: `irq-stat-correlate`

Stack **0006b + 0007 + correlate** (`t_ms` common, `cntl_write`, `/proc/interrupts`).

**Pass criteria for closing delivery boundary:**

```text
t≈50ms   amd_manager  STAT&mask=0x4
t≈50–5000ms   pci-ps       irq_handler_enter  (absent)
/proc/interrupts IRQ164 count unchanged
```

→ boundary: `ACP_EXTERNAL_INTR_STAT1` → GSI/IO-APIC → Linux IRQ 164.

See [0007-irq-delivery-trace.md](0007-irq-delivery-trace.md) · build `--experiment irq-stat-correlate --delay 50`
