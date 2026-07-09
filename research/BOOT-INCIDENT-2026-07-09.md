# Boot incident — 2026-07-09 22:27 (between matrix #21 and #22)

> **English (canonical)** | [Español](es/INCIDENTE-ARRANQUE-2026-07-09.md)

**Status:** recovered by second reboot (matrix boot #22)  
**Not in fw-matrix:** validation never ran (system hung before `snd-repair-fw-validation`)

---

## Timeline (journal `-b -1`, proc boot_id not logged)

| Time | Event |
|------|-------|
| 22:27:03 | Kernel boot |
| 22:27:06 | **systemd ordering cycle** — `snd-repair-fw-validation.service` job **deleted** |
| 22:27:06 | `snd_pci_ps` enables `0000:c4:00.5` |
| 22:27:08 | `px13-audio-rebind.service` starts |
| 22:27:08 | `px13-audio-fix`: **PCI unbind** `0000:c4:00.5` |
| 22:27:09 | Kernel in `snd_acp63_remove` / `unbind_store` — card1 sysfs torn down |
| 22:27:34+ | **Soft lockups** — `apport`, `plymouth`, `kworker` (23s → 137s) |
| ~22:29 | User forced **second reboot** |
| 22:30:09 | Boot #22 — px13 completed (unbind+bind+speaker-test), FW OK |

---

## Root cause (boot collapse)

1. **Primary:** `px13-audio-rebind` **PCI unbind** during early boot (`multi-user.target`, ~5s after kernel) blocked the bus → **soft lockup**. Same class as 2026-07-09 17:26 incident (brainchillz unbind timeout).

2. **Secondary:** systemd **ordering cycle** involving `snd-repair-fw-validation.service` ↔ `graphical.target` ↔ `multi-user.target` — validation job dropped on that boot.

3. **Not the cause:** `speaker-test` never ran — unbind never returned.

---

## Mitigations applied (snd_repair)

| Change | Purpose |
|--------|---------|
| `PX13_SKIP_SPEAKER_TEST=1` | No pink noise on boot/resume |
| `PX13_SKIP_PCI_ON_BOOT=1` | Cold boot: skip PCI reset; resume still uses PCI |
| Fix `snd-repair-fw-validation.service` | Remove `Before=default.target` cycle |
| Drop-in on `px13-audio-rebind` | Load `/etc/default/px13-snd-repair` |

Install:

```bash
sudo ~/snd_repair/scripts/install-px13-audio-fix.sh
sudo sed -i 's/After=sound.target default.target/After=sound.target multi-user.target px13-audio-rebind.service/' /etc/systemd/system/snd-repair-fw-validation.service
sudo systemctl daemon-reload
```

---

## Evidence files

- `validation/boot-logs/boot-021.log` — prior OK boot (22:22)
- `validation/boot-logs/boot-022.log` — recovery boot (22:30)
- `research/snapshots/20260709-boot-collapse/` — journal extract + snapshot

---

## Matrix note

Boots **#21** and **#22** both show `:8=OK` but **#21 was an earlier session** (22:22). The **failed** 22:27 boot has **no matrix row** — treat suspend/resume stats unchanged.
