# Contribuir

> [English](../CONTRIBUTING.md) | **Español**

## Antes de abrir un issue

Incluir:

- `uname -r`
- Modelo (p. ej. HN7306EAC)
- Si el firmware propietario está instalado
- `dmesg | grep -i tas2783`
- Script usado: `build-from-upstream.sh` (recomendado) o `build-production-modules.sh`

Plantilla: [bug report](../.github/ISSUE_TEMPLATE/bug_report.md).

## Parches

**Uso normal:** `build-from-upstream.sh` → series en `upstream/` (sin trazas de depuración).

**Investigación:** `patches/0001–0009` y `build-production-modules.sh` (0009 incluye `ENZOPLAY`).

**Envío al kernel:** parches `upstream/` bajo **GPL-2.0-only**; `Signed-off-by` real; Serie B como RFC.

## Pull requests

- Documentación bilingüe si afecta al usuario (`docs/` + `docs/es/`).
- No subir `linux-source-*`, `.deb`, firmware `.bin`, volcados ACPI.
