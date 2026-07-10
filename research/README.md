# Research material

> **English** | [Español](../docs/es/README.md#referencia-técnica)

Material for diagnosis and **active investigation** on the PX13.

---

| Document | Contents |
|----------|----------|
| **[INVESTIGATION-INDEX.md](INVESTIGATION-INDEX.md)** | Track index A–D |
| **[PRIORITY-DEBUG.md](PRIORITY-DEBUG.md)** | Active P0–P3 status and test protocol |
| **[SUDO-RUNBOOK.md](SUDO-RUNBOOK.md)** | Commands requiring root |
| [track-A-serie-b-suspend.md](track-A-serie-b-suspend.md) | FW `:8` + suspend (P0) |
| [track-B-capture-pin4.md](track-B-capture-pin4.md) | Capture PIN4 `-22` (P2) |
| [track-C-webcam-media0.md](track-C-webcam-media0.md) | Webcam media0 (P3, independent) |
| [track-D-userspace-pipewire.md](track-D-userspace-pipewire.md) | PipeWire / px13 / systemd |
| [FAILURE-REPORT-2026-07-09.md](FAILURE-REPORT-2026-07-09.md) | Consolidated failure report |
| **[phase-6/INDEX.md](phase-6/INDEX.md)** | Phase 6 — observation complete, upstream draft |
| **[phase-7/INDEX.md](phase-7/INDEX.md)** | **Phase 7** — active bring-up experiments (A–D) |

**Quick snapshot:**

```bash
~/snd_repair/scripts/investigation-snapshot.sh track-A-test-1
# → research/snapshots/<tag>/
```

---

## `acpi_debug/`

ACPI table dump (DSDT, SSDT, etc.) for the ProArt PX13. Useful to correlate SoundWire nodes with DisCo.

Regenerate with `acpidump`, `iasl`. `.dat` / `.dsl` files are in `.gitignore`.
