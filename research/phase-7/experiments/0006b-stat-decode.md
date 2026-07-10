# Experiment 0006b — INTR_STAT / INTR_CNTL decode (observation)

English (canonical). **Observation only** — no `schedule_work`, no ping forcing.

Answers:

1. **What is delayed `STAT=0x4`?** Which register, which named bit?
2. Does **`stat & manager_mask`** become non-zero before RT721 times out?
3. What is **BIT(22)** in `INTR_CNTL=0x400004`?

Patch: `research/phase-7/proposed/0006b-stat-decode.patch` (includes **0006b.1** delayed snapshot)

Full journey: [../JOURNEY.md](../JOURNEY.md)

---

## Prerequisites

```bash
./scripts/prepare-kernel-tree.sh    # linux-source aligned with uname -r
```

Requires `linux-headers-$(uname -r)`, `linux-source-$(uname -r)`, sudo for module install.

If Phase 6 patches fail: `./scripts/regenerate-phase6-amd-patches.sh`  
If 0006b patch fails: `./scripts/regenerate-phase7-0006b.sh`

---

## Build

```bash
./scripts/build-phase7.sh --experiment stat-decode --delay 50
sudo reboot
```

Module param `phase7_delay_ms` (default 0):

- `0` — single snapshot `when=post_D0` (control)
- `50` — second snapshot `when=post_delay` after 50 ms (matches 0005 d50 timing)

Persist across reboot:

```bash
./scripts/phase7-sweep-pre.sh 50    # before reboot
./scripts/phase7-sweep-pre.sh 0     # control run
```

---

## Run p7-0006b-d50 (2026-07-11) — Case 1 confirmed

From `journalctl` (parser missed detail until fix; values were in kernel log):

| Snapshot | STAT1 | STAT&mask | handler |
|----------|-------|-----------|---------|
| `post_D0` | `0x0` | `0x0` | NO |
| `post_delay` (+50 ms) | `0x4` | `0x4` | NO |

**Conclusion:** pending IRQ bit appears for manager=1; **IRQ → handler delivery broken**. Proceed **0006a** after rebuild with compact decode line + timing fix.

Timing bug: `t_since_manager_reset_ms` used `ktime_get()` vs Phase 6 `ktime_get_boottime()` — fixed via `amd_phase6_since_reset_ms()`.

### 0006a follow-up (p7-0006a-d50)

[0006a](0006a-validate-manager-mask.md) **Outcome A:** same STAT evolution; manual `schedule_work` at `post_delay` → full enumeration. See [0006a-run-p7-d50.md](0006a-run-p7-d50.md).

---

```bash
./scripts/phase7-sweep-pre.sh 50
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes p7-0006b-d50
systemctl suspend
./scripts/phase6-hunt.sh post-suspend --save-window
journalctl -k -b 0 | grep -E 'PHASE7 ctx=amd fn=(intr_decode|delay_before_decode)'
```

One suspend per boot (`resume_n=1`).

Compare **two** decode blocks per resume:

| `when=` | Timing |
|---------|--------|
| `post_D0` | Immediately after D0 (0006b) |
| `post_delay` | After `msleep(phase7_delay_ms)` (0006b.1) |

---

## Log probes

```text
PHASE7 ctx=amd fn=intr_decode when=post_D0|post_delay link=%d resume=%d manager=%u t_since_post_D0_ms=%lld t_since_manager_reset_ms=%lld
  manager_mask=0x... INTR_CNTL(%u)=0x... STAT(%u)=0x... STAT&mask=0x...
  STAT0=0x... STAT1=0x... CNTL0=0x... CNTL1=0x...
  ...
```

| Field | Meaning |
|-------|---------|
| `t_since_post_D0_ms` | `0` at `post_D0`; ~`phase7_delay_ms` at `post_delay` |
| `t_since_manager_reset_ms` | Wall time since `manager_reset` (Phase 6 anchor) |

Compare runs without relying on experiment notes alone (`STAT` at 18 ms vs 48 ms).

---

## Decision tree (one suspend, d50)

### Case 1 — IRQ delivery broken (best for 0006a)

```text
post_D0:     STAT1=0  STAT&mask=0  t_since_post_D0_ms=0
post_delay:  STAT1=4  STAT&mask=4  handler=NO
```

Hardware/block sets the manager bit; **IRQ → handler path broken** → proceed **0006a**.

### Case 2 — No pending IRQ

```text
post_D0:     STAT1=0
post_delay:  STAT1=0
```

Pending-IRQ hypothesis weak → revisit why first HW event never asserts.

### Case 3 — Wrong register / instance model

```text
post_delay:  STAT0 changes, STAT1=0, manager=1, mask=0x4
```

Do **not** build 0006a on current instance mapping.

---

## STAT ACK sites (ACP63/ACP70, PX13 path)

Write-1-to-clear: **writing the same bit clears it** (`pci-ps.c` comment). If `STAT&mask` appears then vanishes without handler, check these first.

| Location | Register | When | Bits cleared |
|----------|----------|------|--------------|
| `pci-ps.c` `acp63_irq_handler` | `ACP_EXTERNAL_INTR_STAT` | Handler runs | `ACP_SDW0_STAT`, `ACP_ERROR_IRQ`, `BIT(PDM_DMA_STAT)`, SDW0 DMA |
| `pci-ps.c` `acp63_irq_handler` | `ACP_EXTERNAL_INTR_STAT1` | Handler runs | `ACP_SDW1_STAT`, SDW1 DMA |
| `pci-ps.c` `check_and_handle_acp70_sdw_wake_irq` | `ACP_EXTERNAL_INTR_STAT1` | Wake path | `ACP70_SDW{0,1}_HOST_WAKE_STAT`, PME stats |
| `ps-common.c` `acp70_disable_interrupts` | `ACP_EXTERNAL_INTR_STAT` | ACP disable | Full mask `ACP_EXT_INTR_STAT_CLEAR_MASK` |

**Not in `amd_manager.c`:** manager resume path only **reads** STAT (Phase 6/7 probes). No ACK from SoundWire manager driver on resume.

**Implication:** if `post_delay` shows `STAT&mask=0x4` and a later read shows `0` with no `irq_handler_enter`, either the handler ran (ACK in `pci-ps`) or firmware/hardware cleared the bit — compare handler logs in the same window.

---

## PX13 mapping (verified p7-0006b, 2026-07-11)

| Field | Value |
|-------|-------|
| `link_id` | 1 |
| `instance` / `manager` | **1** (not 0) |
| `manager_mask` | `0x4` = `AMD_SDW1_EXT_INTR_MASK` = `ACP_SDW1_STAT` |
| Handler register | `ACP_EXTERNAL_INTR_STAT1` (pci-ps tests `ACP_SDW1_STAT`) |

Delayed `0x4` from 0005/d50 is **`stat & manager_mask`** for instance 1 — not a mystery bit on SDW0.

---

## BIT(22) in `CNTL(1)=0x400004`

```text
0x400004 = BIT(2) | BIT(22)
BIT(2)   = AMD_SDW1_EXT_INTR_MASK  (manager enable)
BIT(22)  = AMD_SDW0_HOST_WAKE_INTR_MASK  (amd_manager.h)
```

Set by `amd_sdw_host_wake_enable()` / ACP70 wake paths on `ACP_EXTERNAL_INTR_CNTL(1)` — **host wake enable**, not the manager STAT bit. Decode prints `host_wake_sdw0=1`.

---

## Why 0006b.1 exists

| Time | 0005 | 0006b (v1) |
|------|------|------------|
| post-D0 | — | `STAT=0` |
| +50 ms | `STAT=0x4` | *(not measured)* |

0006a cannot act until we know whether **`STAT(instance) & manager_mask`** is set at the delay window.

0006b.1 closes that gap **without** `schedule_work`.

---

## Decode table (reference)

### `ACP_EXTERNAL_INTR_STAT1` — instance 1 / global STAT1

| Bit mask | Symbol | pci-ps handler |
|----------|--------|----------------|
| `0x4` | `ACP_SDW1_STAT` | Yes → `schedule_work(irq_thread)` |
| `0x0C000000` | `ACP70_SDW_HOST_WAKE_MASK` | wake path |
| `0x1F8` | SDW1 DMA (STAT1) | DMA thread |

### Manager enable masks

| instance | `AMD_SDW*_EXT_INTR_MASK` | CNTL bit |
|----------|--------------------------|----------|
| 0 | `0x200000` | BIT 21 |
| 1 | `0x4` | BIT 2 on `CNTL(1)` |

---

## Binary questions

1. **Register aliasing:** `STAT(0)` = `STAT_g` and `STAT(1)` = `STAT1_g`?
2. **Instance mapping:** `link_id=1` → `instance=1` ✅ (confirmed)
3. **Mask consistency:** `CNTL(1)` includes `manager_mask` + `host_wake_sdw0`?
4. **Delayed bit:** At `post_delay`, is `STAT(1)=0x4` and `STAT&mask=0x4`?

---

## Outcomes → next step

| `post_delay` decode | Next |
|---------------------|------|
| `STAT1=0x4`, `STAT&mask=0x4`, no handler | **0006a** — `if (stat & mask) schedule_work(...)` |
| `STAT0=0x4`, `STAT1=0`, `manager=1` | Fix probe/instance model before 0006a |
| `STAT&mask=0` at both snapshots | 0006a likely negative; investigate HW/firmware |
| `STAT&mask=0x4` and handler enters later | No manual schedule needed; compare timing |
| PASS run differs | Golden diff for upstream |

---

## Control run

```bash
./scripts/phase7-sweep-pre.sh 0 && sudo reboot
# expect: only when=post_D0 block in dmesg
```

No witness change — enriches 0006a decision only.
