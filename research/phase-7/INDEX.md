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

**0005-delay-after-d0** — falsification. See [experiments/0005-delay-after-d0.md](experiments/0005-delay-after-d0.md).

```bash
/home/rutrus/snd_repair/scripts/build-phase7.sh --experiment delay-after-d0
sudo reboot

# one sweep point (repeat per MS: 0 5 10 20 50 100):
/home/rutrus/snd_repair/scripts/phase7-sweep-pre.sh 20
# --- reboot; after login: ---
/home/rutrus/snd_repair/scripts/phase7-sweep-post.sh --verify-only
/home/rutrus/snd_repair/scripts/phase7-sweep-post.sh
systemctl suspend
/home/rutrus/snd_repair/scripts/phase7-sweep-post.sh --after-suspend
```

**Do not** loop `reboot` with steps after it — use pre/post scripts.

**Status (2026-07-10):** d20 logged — STAT 0→4 at 20 ms, no handler; run invalid (`resume=3`). See [runs table](experiments/0005-delay-after-d0.md#runs). Next: clean-boot points 0, 5, 10, 50, 100.

---

## Ad-hoc (same boot)

For one-off tests without modprobe.d sweep, use `phase6-hunt.sh` directly — see experiment doc. **Formal sweep** uses `phase7-sweep-pre/post.sh` only.

---

## Documents

| Doc | Content |
|-----|---------|
| [BRINGUP-EXPERIMENTS.md](BRINGUP-EXPERIMENTS.md) | Experiments A–D, patch ids, rules |
| [experiments/0005-delay-after-d0.md](experiments/0005-delay-after-d0.md) | **Falsification** — hypothesis, sweep, stop criteria |
