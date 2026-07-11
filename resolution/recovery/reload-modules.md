# D2 — Reload snd_soc_amd_ps

English (canonical). Track **D**.

**Goal:** module reload mimics partial reboot of ACP/SoundWire stack.

**Status:** `?`

---

## Procedure

```bash
# After failed resume (no audio)
sudo systemctl stop pipewire pipewire-pulse wireplumber 2>/dev/null || true

sudo modprobe -r snd_soc_amd_ps
# May need dependent modules — document rmmod order from lsmod
sleep 2
sudo modprobe snd_soc_amd_ps

# Restart userspace
systemctl --user start pipewire wireplumber 2>/dev/null || true
speaker-test -c2 -t wav -l 1
```

**Capture:** full `modprobe -r` dependency chain on PX13.

---

## Variants

| Variant | When |
|---------|------|
| D2a | Immediately after resume |
| D2b | After 5 s delay |
| D2c | After `echo 1 > .../remove` PCI |

---

## Result

| Run | Variant | Result | Notes |
|-----|---------|--------|-------|
| — | — | — | |
