# D4 / D5 — PCI remove/rescan and bus reprobe

English (canonical). Track **D**.

**Goal:** force PCI re-enumeration and SoundWire bus re-init without full reboot.

**Status:** `?`

---

## D4 — PCI remove + rescan

```bash
ACP=$(lspci -d 1022:15e2 | awk '{print $1}')
DEV=/sys/bus/pci/devices/0000:${ACP}

# DANGER: may affect display/audio together — have reboot ready
echo 1 | sudo tee "${DEV}/remove"
echo 1 | sudo tee /sys/bus/pci/rescan
```

Wait for driver rebind; test audio.

---

## D5 — SoundWire reprobe only

If PCI stays up: trigger `soundwire` bus rescan / driver `unbind`+`bind` on manager device.

Document sysfs path from `/sys/bus/soundwire/`.

---

## Rollback

Reboot if device does not reappear.

---

## Result

| Run | Method | Result | Notes |
|-----|--------|--------|-------|
| — | — | — | |
