# A3 / A5 — Runtime PM and wakeup

English (canonical). Track **A**.

**Goal:** avoid broken resume path by never sleeping the ACP device — or by changing wakeup policy.

**Status:** `?` — see [../TRACKER.md](../TRACKER.md)

---

## A3 — Runtime PM off

```bash
# Find ACP PCI device (1022:15e2)
ACP=$(lspci -d 1022:15e2 | awk '{print $1}')
echo "ACP=$ACP"

# Hold device awake
echo on | sudo tee /sys/bus/pci/devices/0000:${ACP}/power/control

# Optional: disable autosuspend delay
echo -1 | sudo tee /sys/bus/pci/devices/0000:${ACP}/power/autosuspend_delay_ms 2>/dev/null || true
```

**Test:** cold boot audio OK → suspend → resume → `speaker-test -c2 -t wav -l 1`

**Persist (ugly):** udev rule or `systemd-sleep` hook — only after PASS.

---

## A1 / A2 — Force D3cold / D0

Requires ACPI `_PR3` / `_D0` cooperation or kernel `pci_pm` quirks. Document exact sysfs / ACPI method used.

| State | Mechanism to try |
|-------|------------------|
| D3cold | `echo deep > .../power/control` + platform `_PR3` |
| D0 hold | `power/control=on` before suspend |

---

## A5 — Disable wakeups

```bash
echo disabled | sudo tee /sys/bus/pci/devices/0000:${ACP}/device/wakeup
# Also check parent bridge wakeup
```

Contrast with research: probe sets `device_set_wakeup_enable(true)`.

---

## Witness

```bash
journalctl -b -k | grep -E 'acp|sdw|RT721|snd_acp'
cat /sys/bus/pci/devices/0000:${ACP}/power/runtime_status
```

---

## Rollback

```bash
echo auto | sudo tee /sys/bus/pci/devices/0000:${ACP}/power/control
echo enabled | sudo tee /sys/bus/pci/devices/0000:${ACP}/device/wakeup
```

---

## Result

| Run | Date | Result | Notes |
|-----|------|--------|-------|
| — | — | — | |
