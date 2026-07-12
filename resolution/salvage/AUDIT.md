# Framework audit — known execution traps

English (canonical). A bruteforce **FAIL is inconclusive** if the strategy did not execute the claimed transition.

---

## Confirmed traps (PX13, kernel 7.0.0-27)

| Trap | Symptom | Reality | Fix |
|------|---------|---------|-----|
| **pci_reset after unload** | `snd_pci_ps missing` | driver sysfs gone after `rmmod` | PCI action **before** unload |
| **Phantom modules** | `modprobe snd_soc_amd_ps failed` | module does not exist | use `snd_acp_sdw_legacy_mach` / anchor |
| **Partial unload** | `soundwire_amd in use` | `snd_sof_amd_acp` holds bus | expected; not full stack teardown |
| **power/state** | `Permission denied` | PCI uses `power/control` | S050 uses runtime PM only |
| **FALSE_PASS** | `RESULT=PASS` but no audio | `speaker-test` alone insufficient | strict witness (RT721, -110, userspace) |
| **trap:audit** | `modprobe -r` without `-n` in audit | **unloads snd_pci_ps** — card gone, S2 blocked |

---

## Who holds SoundWire?

After anchor unload, typical survivors:

```
soundwire_amd    used by snd_sof_amd_acp
soundwire_bus    used by snd_soc_tas2783_sdw, regmap_sdw_mbq, ...
snd_amd_sdw_acpi used by snd_sof_amd_acp
```

Audit: `run-salvage.sh --audit` or `V005-module-holders`.

---

## Three distinct PCI paths

| Path | sysfs | Effect |
|------|-------|--------|
| unbind/bind | `drivers/snd_pci_ps/unbind` | driver detach/attach |
| modprobe -r/a | module layer | may remove driver dir |
| **remove/rescan** | `devices/.../remove` + `pci/rescan` | **full re-enumeration** |

S150 / S070 test the third path.

---

## SoundWire paths (not tried as salvage before bruteforce)

| Path | sysfs |
|------|-------|
| bus rescan | `/sys/bus/soundwire/rescan` |
| drivers_probe | `/sys/bus/soundwire/drivers_probe` |
| RT721 unbind | `devices/sdw:.../driver/unbind` |
| manager rebind | `platform/drivers/amd_sdw_manager/` |

---

## Resume intercept (not post-failure)

Hook: `resolution/scripts/salvage/hooks/px13-resume-intercept.sh`

Philosophy: run winning sequence **during** `resume`, before RT721 `wait_init_timeout` (~5s).

---

## Hierarchy insight

Bruteforce assumed: `ACP → SoundWire → Codec`

Live holders suggest: `SOF → SoundWire → snd_pci_ps transport → Codec`

Until SOF is torn down, `soundwire_amd` never unloads — all anchor-only strategies collapse to the same partial reset.

---

## Status

| Component | State |
|-----------|-------|
| Topology | `discover-topology.sh` / ST01 |
| Destructive | SD10–SD40 (verify LEVEL reports) |
| Top-down teardown | SD40 |
| Sequence ladder | S100–S160 |
| Bruteforce | **frozen** |
| Resume hook | scaffold |
