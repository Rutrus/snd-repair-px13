# Linux IRQ descriptor boundary — static audit

English (canonical). Addresses investigator question: **is the IRQ masked in Linux after resume** (not ACP `CNTL1`)?

**Scope:** `sound/soc/amd/ps/`, PCI PM interaction, device wakeup flags. **No runtime `/proc/irq/*` capture yet** — optional if patches A–D all fail.

---

## Summary

| Layer | Finding |
|-------|---------|
| **ACP driver** | `devm_request_threaded_irq()` **once at probe**; **no** `disable_irq()` / `enable_irq()` / `synchronize_irq()` in `ps/` |
| **ACP driver** | `device_set_wakeup_enable(&pci->dev, true)` at end of probe |
| **Resume path** | `snd_acp_resume()` → `acp_hw_resume()` only — **does not** touch Linux IRQ API |
| **Handler** | Same descriptor from probe; 8.1 shows **no invocations** after resume, not “handler ignores event” |

**Open:** generic kernel/PCI PM may mask the legacy line during s2idle **without** the ACP driver calling `disable_irq()`. That boundary is **not closed** by static audit alone.

---

## What the driver does

### Probe (`pci-ps.c`)

```text
devm_request_threaded_irq(pci->irq, acp63_irq_handler, acp63_irq_thread, IRQF_SHARED, ...)
device_set_wakeup_enable(&pci->dev, true)
```

- IRQ registered with **`devm_*`** — lifetime tied to device; not freed on system resume.
- **Wakeup enabled** on PCI `struct device` — may interact with `drivers/base/power/wakeirq.c` on platforms that attach a wake IRQ to the device.

### System sleep PM (`pci-ps.c`)

```text
snd_acp_suspend  → acp_hw_suspend   (no disable_irq)
snd_acp_resume   → acp_hw_resume    (no enable_irq)
```

No driver-level IRQ mask/unmask on system sleep path.

---

## What the driver does **not** do

| API | In `ps/`? |
|-----|-----------|
| `disable_irq()` / `disable_irq_nosync()` | **No** |
| `enable_irq()` | **No** |
| `irq_set_irq_wake()` | **No** (directly) |
| `request_irq()` on resume | **No** |
| `free_irq()` on suspend | **No** |

---

## External PM layers (hypothesis — not traced on PX13)

Possible without ACP driver involvement:

1. **PCI core PM** — config space / interrupt pin state across D3/s2idle (platform-dependent).
2. **ACPI `_PRT` / GSI 13** — routing unchanged but line inactive until re-arm.
3. **`wakeirq` subsystem** — if a wake IRQ is bound to `pci->dev`, suspend path may `disable_irq_nosync()` ([`drivers/base/power/wakeirq.c`](../../../linux-source-7.0.0/drivers/base/power/wakeirq.c)).
4. **`/proc/irq/N/` depth / disabled flag** — not captured in Phase 8 runs yet.

---

## Boot vs resume asymmetry (descriptor perspective)

| | Boot | Resume |
|---|------|--------|
| `request_irq` | fresh registration | **same** desc |
| Handler runs on STAT1=0x4 | ✓ | ✗ |
| ACP CNTL1 at event | `0x4` (minimal) | `0x400004` (superset) |

If Linux IRQ were simply “wrong handler,” boot would also fail after probe. Failure appears **after s2idle**, pointing to **descriptor/bridge state**, not handler function body.

---

## Optional falsification — Patch E (after B)

Add to `snd_acp_resume()` **before** `acp_hw_resume()`:

```c
enable_irq(pci->irq);
```

**Binary question:** Was the Linux IRQ line disabled/masked after s2idle?

Patch: [../proposed/0009e-enable-irq-resume.patch](../proposed/0009e-enable-irq-resume.patch). **Order: after B fails, before D.**

## Patch D — `pci_set_master` (last)

Cheap PCI bus-master falsification only if E also fails.

Runtime corroboration (no code change):

```bash
# before suspend / after resume (same boot)
grep . /proc/irq/$(grep ACP_PCI_IRQ /proc/interrupts | awk -F: '{print $1}' | tr -d ' ')/{spurious,smp_affinity,affinity_hint} 2>/dev/null
cat /sys/kernel/irq/$(awk '/ACP_PCI_IRQ/{print $1}' /proc/interrupts | tr -d ' ')/actions 2>/dev/null
```

(Exact sysfs path may vary by kernel version — capture once on PX13 for the run log.)

---

## Related

| Doc | Role |
|-----|------|
| [experiments/0009-falsification-matrix.md](experiments/0009-falsification-matrix.md) | Patches A–D protocol |
| [INVESTIGATOR-QA.md](INVESTIGATOR-QA.md) | Pre-unmask STAT1 timeline |
