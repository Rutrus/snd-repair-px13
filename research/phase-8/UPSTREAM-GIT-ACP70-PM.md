# Upstream git archaeology — ACP70 PM and IRQ path

English (canonical). Static review of **torvalds/linux** history for files that implement ACP70 suspend/resume and legacy IRQ delivery. Kernel tree under test: **7.0.0-27** (Ubuntu); upstream log sampled at **v6.15** tag (2026-07-11).

**Purpose:** Support [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md) and upstream maintainer outreach — not a bisect plan.

**Source:** `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/log/<path>?h=v6.15`

---

## Summary

ACP70 support in `sound/soc/amd/ps/` landed in a **compact February 2025 series** (Vijendar Mukunda, AMD). PM for ACP70 reuses the ACP6.3 pattern:

- `sdw_en_stat` fast path (skip full deinit/init when SoundWire links still enabled at suspend entry).
- Full `acp70_init()` / `acp70_deinit()` when links are disabled.

**No upstream commit** in these files explicitly mentions s2idle resume IRQ re-arm, `request_irq` on resume, or `STAT1` clear. ACP7.0 PM ops were added together with hw_ops split — review those commits for intended resume semantics.

SoundWire side: **host wake** and **device power state** sequences were added/refactored in 2024–2025 (`amd_manager.c`); worth cross-reading with PCI PM order (child suspend clears `SW_EN` before PCI samples `sdw_en_stat`).

---

## `sound/soc/amd/ps/ps-common.c`

| Commit | Subject | PM / IRQ relevance |
|--------|---------|-------------------|
| `db746fff89a1` | ASoC: amd: ps: add acp pci driver hw_ops for acp6.3 platform | Baseline ACP6.3 init/deinit, enable/disable_interrupts (**STAT0 clear only**) |
| `491628388005` | ASoC: amd: ps: add callback functions for acp pci driver pm ops | **Introduces `snd_acp63_suspend/resume` + `sdw_en_stat` fork** |
| `7c0ea26c57b0` | ASoC: amd: ps: add pci driver hw_ops for ACP7.0 & ACP7.1 variants | **`acp70_init/deinit`, `acp70_enable_interrupts`, host_wake CNTL1** |
| `fde277dbcf53` | ASoC: amd: ps: add pm ops related hw_ops for ACP7.0 & ACP7.1 platforms | **`snd_acp70_suspend/resume`** wired to hw_ops |
| `0b6914a0121b` | ASoC: amd: ps: add soundwire dma interrupts handling for ACP7.0 platform | DMA CNTL1 bits — **exonerated** for manager IRQ (boot @ `0x4`) |

**Read priority for maintainers:** `fde277dbcf53`, `7c0ea26c57b0`, `491628388005`.

**Observation:** ACP70 `acp70_disable_interrupts()` matches ACP6.3 — clears **STAT0**, zeros **CNTL0**, disables **ENB**; never touches **STAT1** or **CNTL1**. No later commit in this file's log changes that behaviour before v6.15.

---

## `sound/soc/amd/ps/pci-ps.c`

| Commit | Subject | PM / IRQ relevance |
|--------|---------|-------------------|
| `db746fff89a1` | … hw_ops acp6.3 | Probe, **`pci_set_master`**, **`request_irq`**, `acp63_irq_handler` |
| `3898b189079c` | ASoC: amd: ps: add soundwire wake interrupt handling | **`check_and_handle_acp70_sdw_wake_irq()`** — STAT1 ack, WAKE_EN clear |
| `7c0ea26c57b0` | … ACP7.0 hw_ops | Revision dispatch to ACP70 ops |
| `5f86b16c49a9` | ASoC: amd: Convert to RUNTIME_PM_OPS() & co | PM macro refactor — **verify system sleep path unchanged** |
| `7f91f012c1df` | ASoC: amd: ps: fix for irq handler return status | Handler return value only |

**Read priority:** `3898b189079c` (wake path STAT1 writes), probe path in `db746fff89a1`.

**Observation:** **`request_irq` remains probe-only** across all listed commits. No `pci_set_master` on resume.

---

## `drivers/soundwire/amd_manager.c`

| Commit | Subject | PM / IRQ relevance |
|--------|---------|-------------------|
| `7b54323dde29` | soundwire: amd: refactor existing code for acp 6.3 platform | Baseline manager PM |
| `2c0ae8ef1e5e` | soundwire: amd: add support for ACP7.0 & ACP7.1 platforms | ACP70 manager bring-up |
| `829c3e1cb4a3` | soundwire: amd: set device power state during suspend/resume sequence | **D0/D3** on `AMD_SDW_DEVICE_STATE` |
| `5818ed3636b3` | soundwire: amd: set ACP_PME_EN during runtime suspend sequence | PME in **runtime** suspend — distinct from system sleep |
| `3df75289ddc2` | soundwire: amd: add soundwire host wake interrupt enable/disable sequence | **Host wake CNTL1** in manager |
| `74148bb59e20` | soundwire: amd: clear wake enable register for power off mode | **`power_off` suspend** path |
| `dcc48a73eae7` | soundwire: amd: change the soundwire wake enable/disable sequence | Wake sequence refactor |

**Read priority:** `829c3e1cb4a3`, `74148bb59e20`, `3df75289ddc2` for suspend/resume ordering with PCI parent.

---

## Cross-file timeline (upstream intent)

```text
2025-02  ACP7.0 PCI + ps-common PM ops land (init/deinit, sdw_en_stat fork)
2025-02  ACP7.0 DMA IRQ handling (CNTL1 watermark bits)
2024–25  amd_manager: device state, host wake, power_off wake clear
```

**Gap in public history:** no commit message describes **legacy PCI IRQ delivery after system resume** for ACP70. That aligns with our finding: behaviour may be assumed (probe-time `request_irq` sufficient) or handled outside these files (platform/firmware).

---

## Suggested maintainer pointers

When filing upstream, cite:

1. **`491628388005`** — `sdw_en_stat` fast path semantics after manager disables `SW_EN`.
2. **`7c0ea26c57b0` / `fde277dbcf53`** — ACP70 init/deinit vs resume full path.
3. **`3898b189079c`** — whether wake handler STAT1 ack path should run on system resume.
4. **`829c3e1cb4a3` + `74148bb59e20`** — manager/PCI ordering for `power_off` s2idle.

Links (replace `v6.15` with current tag when sending):

- ps-common: `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/log/sound/soc/amd/ps/ps-common.c`
- pci-ps: `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/log/sound/soc/amd/ps/pci-ps.c`
- amd_manager: `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/log/drivers/soundwire/amd_manager.c`

---

## Local repo note

`linux-source-7.0.0/` in this workspace is an **extracted package**, not a git checkout — use kernel.org log above for history. Local tree includes Phase 6/7/8 **observation printk** (not upstream).

---

## Related

| Doc | Role |
|-----|------|
| [ACP-BOOT-VS-RESUME-REGISTERS.md](ACP-BOOT-VS-RESUME-REGISTERS.md) | Register matrix boot vs resume |
| [ACP-IRQ-REGISTER-OWNERSHIP.md](ACP-IRQ-REGISTER-OWNERSHIP.md) | Static ownership audit |
| [../phase-6/UPSTREAM-REPORT-DRAFT.md](../phase-6/UPSTREAM-REPORT-DRAFT.md) | Submittable report |
