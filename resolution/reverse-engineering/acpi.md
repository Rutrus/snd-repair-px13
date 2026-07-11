# G1 — ACPI audit (_DSM, _PR3, _D0, _D3)

English (canonical). Track **G**.

**Goal:** find platform methods Linux never calls — common on OEM audio paths.

**Status:** `?`

---

## Scope

| Object | Methods |
|--------|---------|
| ACP PCI device | `_PR0`, `_PR3`, `_D0`, `_D3`, `_PS0`, `_PS3` |
| SoundWire nodes | `_DSM`, `_CRS`, `_PRS` |
| Parent scope | ASUS-specific UUIDs |

---

## Local sources

| Source | Path |
|--------|------|
| ACPI dump | `research/acpi_debug/` (regenerate with `acpidump` + `iasl`) |
| Linux ACPI trace | `echo 1 > /sys/kernel/debug/acpi/acpi_debug_trace` (careful — verbose) |

---

## Experiments

| Id | Action | Risk |
|----|--------|------|
| G1a | Static table diff vs Windows dump | none |
| G1b | `acpi_call` / `_DSM` invoke on resume | **high** — test with reboot ready |
| G1c | ACPI override SSDT (resolution only) | **high** |

---

## Research link

Track F in [../../research/tracks/TRACK-F-ACPI-GPP4.md](../../research/tracks/TRACK-F-ACPI-GPP4.md) — historical; resolution owns **resume-specific** ACPI now.

---

## Result

| Method | Present? | Called on Linux resume? | Windows calls? | Notes |
|--------|----------|-------------------------|----------------|-------|
| — | — | — | — | |
