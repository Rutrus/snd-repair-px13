# Salvage — destroy and rebuild by layer

English (canonical). **Not bruteforce. Not lab.**

> We do not know what is broken. Discover the live tree, destroy one level at a time, verify it is gone, rebuild.

---

## Key insight (PX13 audit)

```
snd_sof_amd_acp holds soundwire_amd
```

Anchor-only `rmmod snd_pci_ps` is a **partial reset**. S010–S060 were often the same operation. Full teardown requires **SOF → SoundWire** after PCI driver removal.

---

## Three campaigns

| Campaign | Goal | Steps |
|----------|------|-------|
| **SALVAGE-TOPOLOGY** | Discover live tree (no hardcoded names) | ST01 |
| **SALVAGE-DESTRUCTIVE** | Destroy one full layer, verify gone | SD10–SD40 |
| **SALVAGE-SEQUENCE** | Incremental ladder (original) | S100–S160 |

---

## Workflow

```bash
# 0. Boot audio OK?
sudo ~/snd_repair/resolution/scripts/salvage/run-salvage.sh --restore

# 1. Topology (always first)
sudo ~/snd_repair/resolution/scripts/salvage/run-salvage.sh --topology

# 2. Framework audit (read-only)
sudo ~/snd_repair/resolution/scripts/salvage/run-salvage.sh --audit

# 3. S2 + destructive campaign
sudo ~/snd_repair/resolution/scripts/s2-reproduce.sh
sudo ~/snd_repair/resolution/scripts/salvage/run-salvage.sh --from-s2 --campaign SALVAGE-DESTRUCTIVE
```

Single step:

```bash
sudo ~/snd_repair/resolution/scripts/salvage/run-salvage.sh --from-s2 --strategy SD10
```

---

## Destructive steps

| ID | Destroys | Verify |
|----|----------|--------|
| **SD10** | PCI `remove+rescan` | device returns, driver binds |
| **SD20** | SOF then SoundWire modules | `LEVEL` report: sw=no |
| **SD30** | SOF stack only | `sof=no` |
| **SD40** | Full top-down teardown + rebuild | 3 levels cleared |

Each run logs `LEVEL … pci_bound= sdw_devs= sof= sw=` before/after.

---

## Top-down teardown order (SD40)

```
userspace → machine/codec → snd_pci_ps → SOF → SoundWire → rebuild
```

---

## Resume intercept

[hooks/README.md](../scripts/salvage/hooks/README.md) — run winning step during `post` resume, before RT721 timeout.

---

## Related

- [AUDIT.md](AUDIT.md) — execution traps
- [TRACKER.md](TRACKER.md)
- [bruteforce/README.md](../bruteforce/README.md) — frozen until salvage finds a sequence
