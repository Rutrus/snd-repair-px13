# PX13 resume intercept hook (scaffold)

English (canonical). **Intercept failure during resume** — not cure after timeout.

---

## Install (manual, test only)

```bash
sudo install -m 755 \
  ~/snd_repair/resolution/scripts/salvage/hooks/px13-resume-intercept.sh \
  /usr/lib/systemd/system-sleep/px13-audio-salvage
```

Remove when done: `sudo rm /usr/lib/systemd/system-sleep/px13-audio-salvage`

---

## Behaviour

On `post` resume:

1. sleep 1s (let PCI D0 settle)
2. SoundWire bus rescan (S120)
3. RT721 reprobe if needed (S130)
4. optional: manager rebind (S140) — enable via `PX13_SALVAGE_HOOK_MANAGER=1`
5. log to `/var/log/snd-repair-salvage/hook-*.log`

Does **not** run full module unload by default (too slow for resume window).

---

## Tune

| Env | Default | Effect |
|-----|---------|--------|
| `PX13_SALVAGE_HOOK=1` | required | hook active |
| `PX13_SALVAGE_HOOK_MANAGER=0` | off | skip S140 on resume |
| `PX13_SALVAGE_HOOK_PCI=0` | off | never remove+rescan on resume (too risky) |

Set in `/etc/default/px13-audio-salvage` or export before suspend.

---

## Goal

If S120 or S130 alone fixes S2 when run **before** RT721 timeout, this hook is the production workaround path.

Test order:

1. Find winning step via `run-salvage.sh --from-s2`
2. Enable only that step in hook
3. `s2-reproduce` with hook installed
