# F1 — Windows / ASUS driver reverse engineering

English (canonical). Track **F**.

**Goal:** compare **working** Windows resume with Linux failure — timings, register writes, resets, ACPI calls.

**Status:** `?`

---

## Questions

| # | Question |
|---|----------|
| 1 | Does ASUS audio driver call ACPI `_DSM` on resume? |
| 2 | How many ms between D0 and first IRQ enable? |
| 3 | Double manager reset? |
| 4 | Polling instead of IRQ? |
| 5 | Extra MMIO writes not in `snd_soc_amd_ps`? |

---

## Tools

| Tool | Use |
|------|-----|
| ETW | ACP / audio provider trace |
| ProcMon | ACPI, registry, device IOCTL |
| WinDbg | kernel driver breakpoints (if symbols) |
| ACPI dump | Compare DSDT/SSDT with Linux `acpi_debug/` |

---

## Deliverables

| Artifact | Path |
|----------|------|
| Resume timeline | `windows-resume-timeline.csv` |
| Register write log | `windows-mmio-writes.md` |
| ACPI method trace | link to track G |

---

## Linux correlation

Map each Windows step to Linux function in [../../research/phase-8/ACP-BOOT-VS-RESUME-CALLS.md](../../research/phase-8/ACP-BOOT-VS-RESUME-CALLS.md).

---

## Result

| Session | Date | Finding | Linux gap candidate |
|---------|------|---------|---------------------|
| — | — | — | |
