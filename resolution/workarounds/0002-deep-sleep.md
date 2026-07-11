# A4 — deep sleep instead of s2idle

English (canonical). Track **A**.

**Goal:** use S3 (`deep`) or platform `mem_sleep` mode where ACPI/PCI PM path may differ from s2idle.

**Status:** `?` — see [../TRACKER.md](../TRACKER.md)

---

## Check available modes

```bash
cat /sys/power/mem_sleep
# common: s2idle [deep]
```

---

## Try deep (S3)

```bash
# One-shot
echo deep | sudo tee /sys/power/mem_sleep
systemctl suspend
```

Or kernel cmdline: `mem_sleep_default=deep`

**Caveat:** PX13 may not support S3; if suspend fails or hangs, revert immediately.

---

## Witness

- Does machine actually enter deep? (`journalctl` PM trace)
- Same RT721 `-110` or different failure mode?

---

## Rollback

```bash
echo s2idle | sudo tee /sys/power/mem_sleep
```

---

## Result

| Run | Date | Result | Notes |
|-----|------|--------|-------|
| — | — | — | |
