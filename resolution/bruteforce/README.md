# Bruteforce recovery — find ANY working sequence

English (canonical). **Frozen** as of 2026-07-12.

**Unified model:** [../research/UNIFIED-CAUSAL-MODEL.md](../research/UNIFIED-CAUSAL-MODEL.md)

**Result:** **negative experiment** — no sequence restores PCM2 `hw_params` without reboot. remove/rescan, module reload, FLR (when possible), runtime PM all **reconverge to `hw:1,2` EINVAL**. This **rules out** PCI/enumeration as the fix; it supports the unified model (state lives in SmartAmp/ASoC layer).

**Active line:** [../research/track-PCM-smartamp-hwparams.md](../research/track-PCM-smartamp-hwparams.md)

Do **not** add strategies until Q1 (rejecting callback) closes.

---

## Two phases

### 1. Validate actions (run first)

Confirm each action **actually occurs** before interpreting FAIL as "idea does not work".

```bash
sudo ~/snd_repair/resolution/scripts/bruteforce/run-bruteforce.sh --validate
sudo ~/snd_repair/resolution/scripts/bruteforce/run-bruteforce.sh --validate --phase unload
```

| Phase | Checks |
|-------|--------|
| `modules` | `lsmod`, `modinfo`, `modprobe -r -va snd_pci_ps` plan |
| `pci` | real driver path, bind state, FLR/remove sysfs |
| `objects` | `/sys/class/sound`, soundwire, `/proc/asound` baseline |
| `holders` | refcnt, `Used by`, `fuser /dev/snd` |
| `unload` | kernel-objects delta across anchor unload + reload |

Logs: `/var/log/snd-repair-bruteforce/ko-*.txt`

### 2. Recovery bruteforce

```bash
# Do NOT run --validate --phase unload immediately before this (reloads audio)
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/bruteforce/run-bruteforce.sh --from-s2
```

**PASS gates** (L1–L4 automated; L5 audible = manual):

| Layer | Check |
|-------|-------|
| L1 Kernel | `/proc/asound/cards` + `aplay -l` |
| L2 ALSA | `speaker-test` on **hw:X,Y** (plughw informational only) |
| L3 PipeWire | real sink present (`wpctl` / `pactl`, not Dummy only) |
| L4 Routing | default sink = real hardware |
| RT721 | sysfs `attached` |
| Kernel | no RT721 `-110` in journal |
| L5 | audible sound (manual) |

`RESULT=PARTIAL` = kernel+ALSA hw OK but PipeWire/userspace broken — **does not stop the runner**.  
`RESULT=FALSE_PASS` = plughw speaker-test only — **does not stop the runner**.

Diagnostic: `sudo resolution/scripts/witness-audio-chain.sh`

---

## Priority (user order)

1. **R200** — anchor unload/load (`modprobe -r -va snd_pci_ps`)
2. **R300** — PCI reprobe **before** unload, then full reload
3. **R550** — PCI remove + rescan (not just unbind)
4. **R500** — FLR / reprobe while bound
5. **R100** — cheap software restarts

**Default order:** R200 → R300 → R550 → R500 → R100 → R400 → R700 → R600

---

## Lessons from RUN-01 (2026-07-12)

| Issue | Cause | Fix |
|-------|-------|-----|
| `pci_reset: snd_pci_ps missing` | reprobe ran **after** `rmmod snd_pci_ps` | S020/S040: PCI action **before** unload |
| `rmmod … skipped/failed` | wrong module list; deps not logged | anchor `modprobe -r -va`; verbose reason |
| `modprobe snd_soc_amd_ps failed` | module does not exist on 7.0.0-27 | skip via `modinfo`; use anchor load |
| `power/state EPERM` | normal on PCI | use `power/control` + `runtime_status` only |
| All strategies FAIL at same point | stack reload may be incomplete | validate unload delta (V004) |

---

## Layout

```
resolution/bruteforce/
├── README.md
├── TRACKER.md
└── campaigns/

resolution/scripts/bruteforce/
├── _lib.sh
├── run-bruteforce.sh
├── validate/          V001–V004
└── strategies/        S001 … S070
```

---

## Related

- Frozen causal work: branch `resolution/lab` @ 114c067
- [campaigns/README.md](campaigns/README.md)
