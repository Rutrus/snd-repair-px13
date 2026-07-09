# snd_repair — Audio ASUS ProArt PX13 en Linux

Solución documentada para altavoces integrados **TAS2783** (SoundWire) en **ASUS ProArt PX13 (HN7306EAC)** bajo Ubuntu / Linux Mint con kernel 7.0+.

> [English](README.md) · Licencia: [MIT](LICENSE) (docs/scripts); parches kernel [GPL-2.0-only](LICENSE)

---

## Qué es y qué no es este repo

| **Sí es** | **No es** |
|-----------|-----------|
| Investigación + parches reproducibles para altavoces PX13 | Fix genérico para todos los portátiles ASUS |
| Series limpias para upstream (`upstream/`) | Redistribución de firmware propietario ASUS/TI |
| Scripts para recompilar tras actualizar el kernel | Paquete DKMS firmado (aún) |
| Documentación bilingüe (EN por defecto, ES en `docs/es/`) | Validado en todos los kernels (solo probado 7.0.0-27-generic) |

---

## Relación con [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix)

| Proyecto | Enfoque |
|----------|---------|
| **brainchillz** | Etapa 1 — firmware propietario ASUS |
| **snd_repair** | Etapa 2 — bugs del kernel (problemas A/B/C), upstream |

**Orden recomendado:** firmware (brainchillz o [`docs/es/01-instalacion-firmware.md`](docs/es/01-instalacion-firmware.md)) → `./scripts/build-from-upstream.sh` → reboot.

---

## Inicio rápido

| Paso | Qué | Dónde |
|------|-----|-------|
| 1 | Firmware ASUS | [`docs/es/01-instalacion-firmware.md`](docs/es/01-instalacion-firmware.md) |
| 2 | Árbol de fuentes | `./scripts/prepare-kernel-tree.sh` |
| 3 | **Módulos limpios (recomendado)** | `./scripts/build-from-upstream.sh` |
| 4 | Verificar | `speaker-test -D plughw:1,2 -c 2 -t wav -l 1` |

---

## Producción vs laboratorio

**Recomendado:** `upstream/` — series A+B+C sin trazas `ENZOPLAY`:

```bash
./scripts/build-from-upstream.sh
```

**Laboratorio:** `patches/0001–0009` — cronología de investigación con instrumentación. Usar `build-production-modules.sh` solo para reproducir trazas.

---

## Más documentación

[`docs/es/README.md`](docs/es/README.md) · [`docs/es/REVISION-TECNICA.md`](docs/es/REVISION-TECNICA.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md)

**Firmware:** binarios propietarios; no incluidos en el repo. Ver instalación en docs.

---

*Julio 2026 — ASUS ProArt PX13*
