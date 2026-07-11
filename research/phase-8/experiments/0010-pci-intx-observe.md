# Experiment 0010 — PCI INTx status at STAT1 events

English (canonical). Phase **8.3** — **observation only** (no behaviour change).

**Question:** When `STAT1=0x4` at `post_delay`, is `PCI_STATUS_INTERRUPT` set in config space?

**Prerequisite:** [STAT1-TO-PCI-BOUNDARY.md](../STAT1-TO-PCI-BOUNDARY.md) — no MMIO bridge register in public headers.

---

## Why this experiment is justified

PCI Local Bus Spec rev 3.0, Status register bit 3:

> Reflects the state of the interrupt in the device/function. When Interrupt Disable (Command bit 10) is 0 and Interrupt Status is 1, the device's INTx# signal will be asserted.

The kernel uses the same semantics in `pci_check_and_mask_intx()` (`drivers/pci/irq.c`).

**Platform:** ACP70 uses legacy INTx (`msi=0`, `ACP_PCI_IRQ`, GSI 13). Not MSI.

**Caveat:** Some devices violate the spec (INTx# asserted but status bit 0). Log **`intx_disable`** alongside **`intx_status`** so ambiguous cases are visible. If `intx_disable=1`, status bit may be set while pin is not asserted per spec.

---

## Build

```bash
./scripts/build-phase8-0010.sh
./scripts/phase7-sweep-pre.sh 50
sudo reboot
```

---

## Run (one cycle)

```bash
./scripts/phase8-irq-snapshot.sh pre-suspend
systemctl suspend
./scripts/phase8-irq-snapshot.sh post-resume
journalctl -k -b 0 | grep -E 'PHASE10.*pci_intx|intr_decode when=post_delay'
```

Boot baseline (same boot, before suspend):

```bash
journalctl -k -b 0 | grep 'PHASE10.*when=irq_handler.*resume=0'
```

---

## Interpretation (nuanced — not binary on intx_status alone)

Compare **boot** `when=irq_handler resume=0` vs **resume** `when=post_delay resume=1`.

| Case | Resume @ post_delay | Boot @ irq_handler | Reading |
|------|---------------------|-------------------|---------|
| **A** | `stat1=0x4 intx_status=1` handler=0 | `intx_status=1` | Device reports PCI interrupt pending; does **not** prove pin reached IO-APIC — narrows to PCI/IRQ subsystem |
| **B** | `stat1=0x4 intx_status=0` | `intx_status=1` | STAT latched but PCI status never set — **ACP70 bridge / firmware** |
| **C** | Same bit pattern boot and resume | Same | `PCI_STATUS.Interrupt Status` **does not discriminate** on this platform — do not over-claim in upstream report |

Always note `intx_disable=1` → INTx masked at PCI command; status bit may not reflect pin per spec.

Log fields (single line): `when resume irq stat1 intx_disable intx_status t_mgr_ms`

---

## Interpretation (legacy table)

---

## After 0010

- **Clear split** → include in upstream minimal report.
- **Ambiguous** (e.g. status never set on boot either) → skip hardware claim; upstream report without 0010 table row.
- **Either way** → close experimental phase; no more driver patches unless maintainer points to specific register.

---

## Related

| Doc | Role |
|-----|------|
| [proposed/0010-pci-intx-status-observe.patch](../proposed/0010-pci-intx-status-observe.patch) | Implementation sketch |
| [experiments/0009-run-falsify-E-fail.md](0009-run-falsify-E-fail.md) | Last falsification |
