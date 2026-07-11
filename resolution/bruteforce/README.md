# Bruteforce recovery — find ANY working sequence

English (canonical). **Different goal from `resolution/lab`.**

| Lab (`resolution/lab`) | Bruteforce (`resolution/bruteforce`) |
|------------------------|--------------------------------------|
| Why does it fail? | Does **anything** restore audio? |
| Evidence graph | First **PASS** wins |
| Maintainer | PX13 workaround |

> **Does a command sequence return audio without reboot?**

Ugly OK · 10s OK · module unload OK · PX13-only OK.

---

## Priority (user order)

1. **R200** — full ALSA/SoundWire module stack reload
2. **R300** — complete sequences (stop → unload → reprobe → load → start)
3. **R500** — aggressive PCI reset (FLR)
4. **R100** — cheap software restarts
5. **R400/R600/R700** — runtime PM, second suspend, ACPI

---

## Quick start

```bash
# 1. Reproduce S2
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh

# 2. Run all strategies (stops on first PASS)
sudo ~/snd_repair/resolution/scripts/bruteforce/run-bruteforce.sh --from-s2

# 3. One campaign only
sudo ~/snd_repair/resolution/scripts/bruteforce/run-bruteforce.sh --from-s2 --campaign R300

# 4. Loop for an hour (keep trying after FAIL)
sudo ~/snd_repair/resolution/scripts/bruteforce/run-bruteforce.sh --from-s2 --loop
```

Logs: `/var/log/snd-repair-bruteforce/` (or `$TMPDIR`)

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
└── strategies/
    S001 … S060
```

---

## Related

- Frozen causal work: branch `resolution/lab` (commit before this branch)
- [campaigns/README.md](campaigns/README.md)
