# Pre-reboot technical state

> **English** | [Español](es/firmware-pre-reboot.md)

Technical snapshot before `sudo reboot` during firmware symlink matrix setup.

---

## System state (pre-reboot)

### Confirmed facts

1. **Hardware healthy:** `ls -la /sys/bus/soundwire/devices/` shows all **three** chips: Realtek headphone codec (`rt721`) and **two** TI amplifiers at `0x8` (left) and `0xB` (right).
2. **Root cause is chip firmware (not SOF topology):** dmesg shows `-22` (EINVAL) with `error playback without fw download` — the driver refuses playback without calibration bytes in the amplifier silicon.
3. **Cascade failure:** If firmware load fails on the first amp (`0x8`), ALSA/ASoC aborts speaker block init; the second amp (`0xB`) may never register in the mixer.

---

## Symlink matrix prepared in `/usr/lib/firmware/`

Because the driver does not log the exact firmware filename (depends on ACPI parsing), a **compatibility symlink matrix** was created:

| Path / symlink | Variant covered |
|----------------|-----------------|
| `ti/1714-1-8.bin` / `ti/1714-1-b.bin` | Standard TI layout (lowercase) |
| `1714_1_8.bin` / `1714_1_B.bin` | Underscore format (common in ASUS patches) |
| `ti/tas2783-8.bin` / `ti/tas2783-b.bin` | Generic device ID naming |
| `tas2783-1714-1-0x8.bin` / `tas2783-1714-1-0xb.bin` | Explicit bus address (hex) |

---

## Immediate steps after reboot

```bash
sudo dmesg | grep -i tas2783
```

### Two expected scenarios

* **Scenario A (success):** `error playback without fw download` lines disappear; clean codec init; right channel may work.
* **Scenario B (persistence):** error remains — kernel expects a different filename; capture the exact path with `strace` or `perf` on bus initialization.

### Reboot

With the symlink matrix deployed, proceed to reboot:

```bash
sudo reboot
```

After boot, repeat the `dmesg` check and record the outcome for the next diagnostic iteration.
