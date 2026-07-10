# Phase 7 — Bring-up experiments (ACP70)

> **Branch:** `research/suspend-lifecycle` (or `research/phase7-bringup` when split)  
> **Plan:** [BRINGUP-EXPERIMENTS.md](BRINGUP-EXPERIMENTS.md)  
> **Phase 6 (closed):** [../phase-6/INDEX.md](../phase-6/INDEX.md)

English (canonical). Phase 6 **observation** is complete. Phase 7 asks: **what change makes the first HW event appear?**

---

## Mode shift

| | Phase 6 | Phase 7 |
|--|---------|---------|
| Method | `printk` / register read | **Controlled intervention** |
| Goal | Delimit break | **First behaviour change** |
| Another identical FAIL | Useful (N/N) | **Low value** |

---

## First experiment (ready)

**0005-delay-after-d0** — falsification, not fix. See [experiments/0005-delay-after-d0.md](experiments/0005-delay-after-d0.md).

```bash
/home/rutrus/snd_repair/scripts/build-phase7.sh --experiment delay-after-d0
sudo reboot
echo 20 | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-reboot --notes p7-0005-d20
systemctl suspend
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-suspend
```

Sweep `0, 5, 10, 20, 50, 100` — close timing hypothesis if all match control.

---

## Run protocol (unchanged witness)

```bash
/home/rutrus/snd_repair/scripts/build-phase7.sh --experiment delay-after-d0   # not build-phase6
sudo reboot
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-reboot --notes p7-0005-d20
systemctl suspend
/home/rutrus/snd_repair/scripts/phase6-hunt.sh post-suspend
```

Compare to baseline FAIL (0015): any change in `intr_stat_post_delay`, handler, or ATTACHED?

---

## Documents

| Doc | Content |
|-----|---------|
| [BRINGUP-EXPERIMENTS.md](BRINGUP-EXPERIMENTS.md) | Experiments A–D, patch ids, rules |
| [experiments/0005-delay-after-d0.md](experiments/0005-delay-after-d0.md) | **Falsification** — hypothesis, sweep, stop criteria |
