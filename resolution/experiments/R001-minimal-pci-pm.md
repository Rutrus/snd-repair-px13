# R001 — Minimal PCI PM reproduction

English (canonical). Track **B**.

**Goal:** strip the stack to `PCI device → suspend → resume → read registers`. If STAT/IRQ gap reproduces without ALSA, machine driver, and codecs, half the tree is eliminated.

**Status:** `?`

---

## Target stack

```text
1022:15e2 (ACP70 PCI)
    ↓
snd_acp_suspend / snd_acp_resume  (or unbind driver + raw PCI PM)
    ↓
mmio read: ACP_EXTERNAL_INTR_STAT1, CNTL1, PCI_STATUS
    ↓
/proc/interrupts delta for ACP line
```

**No:** PipeWire, RT721, TAS2783, `snd_soc` machine, SoundWire enumeration wait.

---

## Approaches

### B1a — Minimal module / test kernel module

Load only `snd_acp_pci` / `snd_soc_amd_acp` with probe but no machine driver binding.

### B1b — Unbind audio machine, keep ACP PCI driver

```bash
# Document exact driver names on PX13
echo 'DRIVER_NAME' | sudo tee /sys/bus/pci/devices/0000:XX:XX.X/driver/unbind
```

### B1c — userspace PCI access (last resort)

`pciutils` + `/dev/mem` — only if driver unbind is insufficient.

---

## Witness template

| Point | Boot | Resume |
|-------|------|--------|
| STAT1 & 0x4 | | |
| PCI_STATUS.INTx | | |
| /proc/interrupts ACP | | |
| handler_since_pm | | |

---

## Pass/Fail interpretation

| Outcome | Meaning |
|---------|---------|
| Same gap without SDW/ALSA | Problem is **ACP/PCI/IRQ**, not codec layer |
| Gap gone | Upper stack **participates** in failure — revisit assumptions |

---

## Result

| Run | Approach | Result | Notes |
|-----|----------|--------|-------|
| — | — | — | |
