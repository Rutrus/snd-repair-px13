# Research material

> **English** | [Español](../docs/es/README.md#referencia-técnica)

Material de diagnóstico e **investigación activa** del PX13.

---

## Investigación en curso (2026-07-09)

| Documento | Contenido |
|-----------|-----------|
| **[INVESTIGATION-INDEX.md](INVESTIGATION-INDEX.md)** | Índice de tracks A–D |
| [track-A-serie-b-suspend.md](track-A-serie-b-suspend.md) | FW `:8` + suspend (P0) |
| [track-B-capture-pin4.md](track-B-capture-pin4.md) | Capture PIN4 `-22` (P2) |
| [track-C-webcam-media0.md](track-C-webcam-media0.md) | Webcam media0 (P3, **independiente**) |
| [track-D-userspace-pipewire.md](track-D-userspace-pipewire.md) | PipeWire / px13 / systemd |
| [FAILURE-REPORT-2026-07-09.md](FAILURE-REPORT-2026-07-09.md) | Informe consolidado |

**Snapshot rápido:**

```bash
~/snd_repair/scripts/investigation-snapshot.sh track-A-test-1
# → research/snapshots/<tag>/
```

---

## `acpi_debug/`

Volcado ACPI (DSDT, SSDT, etc.) del ProArt PX13. Útil para correlacionar nodos SoundWire con DisCo.

Regenerable con `acpidump`, `iasl`. Archivos `.dat` / `.dsl` en `.gitignore`.
