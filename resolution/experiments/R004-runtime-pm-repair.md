# R004 — Runtime PM repair

English (canonical). **Priority 3.** Recovery **R09** + prevention **M03**.

---

## Hypothesis (engineering, not research)

**System resume** and **runtime resume** are different code paths.

The ACP/SoundWire stack may be broken after `systemctl suspend` → resume, while a **runtime** `suspend → resume` cycle on the same PCI device could re-init hardware correctly.

If true: workaround = trigger runtime PM after every broken system resume. Bug is in **system PM path**, not silicon.

---

## Experiment R09 (recovery — after failure)

Prerequisites: `power/control` was `auto` (or set it before suspend test).

```bash
# After failed system resume:
ACP=$(lspci -d 1022:15e2 | awk '{print $1}')
DEV=/sys/bus/pci/devices/0000:${ACP}

cat "${DEV}/power/control"      # expect auto
cat "${DEV}/power/runtime_status"

# Force runtime suspend (device must be idle enough)
echo auto | sudo tee "${DEV}/power/control"
echo 0 | sudo tee "${DEV}/power/autosuspend_delay_ms" 2>/dev/null || true

# Trigger idle — may need close all PCM handles first
systemctl --user stop pipewire wireplumber 2>/dev/null || true
sleep 2

# Check suspended
cat "${DEV}/power/runtime_status"   # want suspended

# Wake
# open audio or:
echo on | sudo tee "${DEV}/power/control"
sleep 1
echo auto | sudo tee "${DEV}/power/control"

systemctl --user start pipewire wireplumber 2>/dev/null || true
speaker-test -c2 -t wav -l 1
```

Script: [../scripts/recovery/R09-runtime-pm-cycle.sh](../scripts/recovery/R09-runtime-pm-cycle.sh)

---

## Experiment M03 (prevention — on resume hook)

Before suspend:

```bash
echo auto | sudo tee /sys/bus/pci/devices/0000:${ACP}/power/control
```

`systemd-sleep` post-resume:

```bash
# sleep 2
# run R09 sequence automatically
```

If M03 PASS: ship as hook without kernel rebuild.

---

## Witness

| Point | Expect if hypothesis true |
|-------|---------------------------|
| `runtime_status` after system resume | `active` or `suspended` |
| After runtime cycle | `active` + new `runtime_resume` in `dmesg` |
| `speaker-test` | PASS |
| `/proc/interrupts` ACP delta | may increment on runtime resume |

```bash
journalctl -b -k | grep -E 'runtime|acp|snd_acp'
```

---

## Variants

| Id | Variant |
|----|---------|
| R09a | Cycle only ACP PCI device |
| R09b | Cycle + R04 manager rebind after |
| R09c | `power/control=on` 5s → `auto` (force full power transition) |

One variant per run.

---

## Result

| Run | Id | Result | Notes |
|-----|-----|--------|-------|
| — | — | — | |
