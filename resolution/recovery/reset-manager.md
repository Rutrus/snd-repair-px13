# D1 / D3 — Manager and ACP reset after resume failure

English (canonical). Track **D**.

**Goal:** accept IRQ will not arrive; after timeout, force full manager/ACP re-init.

**Status:** `?`

---

## Trigger

Resume → wait for RT721 `-110` or 5 s → run recovery.

---

## D1 — Full ACP reset sequence

Document exact register sequence or ioctl if exposed. May require custom kernel patch that runs **after** failed wait.

---

## D3 — Unregister / recreate manager

```text
detect timeout
    ↓
snd_soc_unregister_card / remove machine link
    ↓
amd_sdw manager teardown
    ↓
re-probe path (as close to boot as possible)
```

---

## Witness

- Second card appear without reboot?
- `aplay` works after recovery script?

---

## Scripts

→ [../scripts/resume-recovery.sh](../scripts/resume-recovery.sh) (stub)

---

## Result

| Run | Method | Result | Notes |
|-----|--------|--------|-------|
| — | — | — | |
