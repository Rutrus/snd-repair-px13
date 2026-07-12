# Rescue mode — aggression tree

English (canonical). **Paused** as of 2026-07-12.

**Unified model:** [../research/UNIFIED-CAUSAL-MODEL.md](../research/UNIFIED-CAUSAL-MODEL.md)

**Result:** **negative experiment** through level D (PCI remove/rescan). Standard Linux re-init paths **do not** restore PCM2 `hw_params`. Strong evidence that bad state is **not** in PCI/SoundWire enumeration alone.

**Active investigation:** [../research/track-PCM-smartamp-hwparams.md](../research/track-PCM-smartamp-hwparams.md) — Q1: name rejecting callback.

No further levels until Q1 closes.

```
rmmod snd_pci_ps alone
  └── snd_sof_amd_acp still holds soundwire_amd
        └── half reload — never probed from zero
```

Level **C** is the first falsifying step: destroy SOF + SoundWire + PCI, verify gone, rebuild.

---

## Aggression tree

| Level | Action | Destroys |
|-------|--------|----------|
| **A** | restart PipeWire | userspace |
| **B** | alsactl + udev + fuser | ALSA state |
| **C** | **full stack destroy + rebuild** | SOF + SW + snd_pci_ps |
| **D** | PCI remove+rescan | PCI enumeration |
| **E** | unbind all SoundWire + drivers_probe | SDW slaves |
| **F** | remove + 10s settle + udev + reload | PCI (long) |
| **G** | second suspend | PM |
| H | kexec | near-reboot |
| I | warm reboot | defeats goal |

---

## Usage

```bash
sudo ~/snd_repair/resolution/scripts/salvage/run-salvage.sh --restore
sudo ~/snd_repair/resolution/scripts/salvage/run-salvage.sh --topology
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh

sudo ~/snd_repair/resolution/scripts/rescue/run-rescue.sh --from-s2
sudo ~/snd_repair/resolution/scripts/rescue/run-rescue.sh --from-s2 --level C
sudo ~/snd_repair/resolution/scripts/rescue/run-rescue.sh --list
```

**PASS** = L1 kernel + **L2 primary PCM** (`hw:1,2`) + L3 real sink + L4 real default (+ RT721 + no -110).  
Diagnostic: `sudo resolution/scripts/witness-pcm-probe.sh`  
**Active investigation:** [../research/PCM2-investigation-framing.md](../research/PCM2-investigation-framing.md)

---

## Invalidated experiments (framework bugs, now fixed)

| Bug | Effect |
|-----|--------|
| pci_reset after unload | driver sysfs gone — reset never ran |
| half reload snd_pci_ps | SOF holds soundwire_amd |
| S050 power/state | file not writable on PCI |
| audit without `-n` | accidentally unloaded driver |
| speaker-test only | FALSE_PASS |
| ALSA any PASS but primary FAIL | S2 SmartAmp `set_params` — see pcm witness doc |
| ALSA OK + Dummy Output | PARTIAL (was false PASS) |

---

## Related

- [salvage/README.md](../salvage/README.md) — topology + audit
- [levels.yaml](levels.yaml)
