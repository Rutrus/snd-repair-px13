# snd_repair — Audio ASUS ProArt PX13 en Linux

Solución documentada para altavoces integrados **TAS2783** (SoundWire) y **audio tras suspend/resume** en **ASUS ProArt PX13 (HN7306EAC)** bajo Ubuntu / Linux Mint con kernel 7.0+.

**Resultado (julio 2026):** estéreo en arranque en frío. Audio post-S2: **W1+W2 + servicio resume brainchillz** — ver [incidente playback silencioso](research/experiments/post-s2-silent-playback-recovery-20260712.md) (12 jul tarde).

> [English](README.md) · Licencia: [MIT](LICENSE) (docs/scripts); parches kernel [GPL-2.0-only](LICENSE)

---

## Solución práctica (uso diario)

Esta es la **pila validada para usuario** (KPI-U). Úsala si quieres un PX13 que sobreviva al **sleep/wake** como un portátil normal.

### ¿Cuándo aplicarlo?

| Situación | ¿Aplicar? |
|-----------|-----------|
| **Sin altavoces** tras instalar Linux | **Sí** — empezar por etapa 1 (firmware) |
| Altavoces OK en **arranque en frío** pero **muertos tras suspend** | **Sí** — necesitas W1+W2 + UCM mic (abajo) |
| Solo **altavoz izquierdo** o capture `-22` en dmesg | **Sí** — parches base (`build-from-upstream.sh`) |
| **Speaker visible pero sin sonido tras S2** | **Sí** — playback silencioso; mantén `px13-audio-resume`; verifica **de oído** |
| **Mic interno ausente** en Ajustes pero playback OK | **Sí** — ejecutar `install-ucm-px13.sh` |
| `arecord -D hw:…` falla con EIO pero **el mic en GNOME funciona** | **No hace falta más** — quirk upstream RW vs MMAP; el escritorio está bien |
| Otro modelo de portátil | **No** — solo PX13 HN7306EAC salvo que portes los parches |

**Probado:** kernel `7.0.0-27-generic` · Ubuntu 26.04 / Linux Mint 22.x.

### Orden de instalación (una vez)

**Requisitos:** [`docs/es/PREREQUISITOS.md`](docs/es/PREREQUISITOS.md) · guía completa: [`docs/es/INSTALACION.md`](docs/es/INSTALACION.md)

```text
Etapa 1 — brainchillz (firmware + UCM base + systemd)
Etapa 2 — parches kernel base (cold boot: estéreo, -22, FW)
Etapa 3 — W1 + W2 (resume: SoundWire + FW TAS2783 tras S2)
Etapa 4 — UCM mic interno (GNOME / PipeWire)
Etapa 5 — px13-audio-resume DESACTIVADO (obligatorio con W1+W2)
```

| Paso | Comando | ¿Una sola vez? |
|------|---------|----------------|
| **1. Firmware + UCM** | brainchillz [`fix-px13-audio.sh`](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) — ver [`docs/es/INSTALACION.md`](docs/es/INSTALACION.md) | **Sí** |
| **2. Kernel base** | `./scripts/prepare-kernel-tree.sh` → `./scripts/build-from-upstream.sh` → **reboot** | Recompilar tras cada kernel |
| **3. Fix resume (W1+W2)** | `sudo ./scripts/build-w1-w2.sh` → **reboot** | Recompilar tras cada kernel |
| **4. Mic interno** | `sudo ./scripts/install-ucm-px13.sh` → `systemctl --user restart wireplumber pipewire` | **Sí** |
| **5. No mezclar** | `sudo systemctl disable --now px13-audio-resume.service` | **Sí** |

**No combines W1+W2 con `px13-audio-resume`.** Tras resume W2 carga FW; ~13 s después px13 resetea PCI → `:8` sin FW → **Dummy Output** ([incidente](research/experiments/post-s2-silent-playback-recovery-20260712.md)).

**Recuperación Dummy Output:** `sudo systemctl disable --now px13-audio-resume.service` → **reboot**.

**No ejecutes** `sudo px13-audio-fix.sh` a mitad de sesión sin **reboot**.

Cierre técnico: [`research/SOLUTION-CLOSURE-KPI-U-20260712.md`](research/SOLUTION-CLOSURE-KPI-U-20260712.md)

### Comprobar que funciona

**Tras arranque en frío:**

```bash
wpctl status                                    # sink Speaker real, no Dummy Output
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**Tras suspend/resume:**

Espera **~30 s** tras despertar (**sin** px13-audio-resume), luego:

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
./scripts/post-s2-user-witness.sh                    # en TTY pregunta si OÍSTE el tono
```

PASS = playback **audible** (confirmas `y`) + mic OK. `--no-audible-confirm` solo para automatización (más débil).

### Tras actualizar el kernel — ¿hay que reaplicar?

**Sí, los módulos del kernel. No, firmware ni UCM.**

| Componente | ¿Sobrevive `apt upgrade`? | Acción con kernel nuevo |
|------------|---------------------------|-------------------------|
| Firmware `.bin` en `/lib/firmware/` | **Sí** | Ninguna |
| UCM (`install-ucm-px13.sh`) | **Sí** | Ninguna |
| Módulos `.ko` parcheados | **No** — ligados a la versión del kernel | Recompilar (abajo) |
| Módulos W1 / W2 (resume) | **No** | Recompilar (abajo) |

```bash
# Tras arrancar en el kernel NUEVO:
./scripts/post-kernel-update.sh    # reconstruye upstream A+B+C
sudo ./scripts/build-w1-w2.sh      # reconstruye fix resume — obligatorio para audio S2
sudo reboot
./scripts/post-s2-user-witness.sh  # comprobación opcional
```

Si omites la recompilación, `modinfo snd_soc_tas2783_sdw | grep vermagic` **no** coincidirá con `uname -r` y volverás al driver stock → problemas de estéreo / resume.

Detalle: [`docs/es/ACTUALIZACION-KERNEL.md`](docs/es/ACTUALIZACION-KERNEL.md)

### ¿Es “definitivo” / upstream?

| Capa | Estado |
|------|--------|
| **Uso escritorio (KPI-U)** | **Parcial** — mic/software OK; **playback audible** requiere resume service + prueba de oído |
| **Merge upstream** | **Aún no** — parches locales `.ko`, no paquete de distro |
| **Hack W2 resume** | Experimental — funciona en PX13; puede refinarse antes del RFC |
| **`arecord` directo (RW) tras S2** | Sigue fallando — PipeWire usa MMAP; no es regresión de usuario |

Trátalo como **listo para uso diario** mientras recompiles módulos tras cada kernel. No es “instalar una vez y olvidar sin mantenimiento”.

### ¿Algo sigue fallando?

| Síntoma | Acción |
|---------|--------|
| Speaker en GNOME pero **sin sonido** | [Playback silencioso](research/experiments/post-s2-silent-playback-recovery-20260712.md) — activa `px13-audio-resume`, espera 15 s; **reboot** si ejecutaste `px13-audio-fix` a mano |
| Dummy Output | W1+W2, firmware, reboot |
| Mic OK, `arecord` EIO | Quirk KPI-K — ignorar si mic GNOME funciona |

1. **Verifica de oído:** `speaker-test -D pipewire …` — no confíes solo en el witness.
2. Módulos: `modinfo snd_soc_tas2783_sdw | grep vermagic` vs `uname -r`.
3. **`px13-audio-resume.service` debe estar enabled** con W1+W2 en PX13.
4. **No** ejecutes `sudo px13-audio-fix.sh` sin planear reboot.

Reversión: [`docs/es/REVERSION.md`](docs/es/REVERSION.md)

---

## Qué es y qué no es este repo

| **Sí es** | **No es** |
|-----------|-----------|
| Investigación + parches reproducibles para altavoces PX13 | Fix genérico para todos los portátiles ASUS |
| Series limpias para upstream (`upstream/`) | Redistribución de firmware propietario ASUS/TI |
| Scripts para recompilar tras actualizar el kernel | Paquete DKMS firmado (aún) |
| Documentación bilingüe (EN por defecto, ES en `docs/es/`) | Validado en todos los kernels (probado 7.0.0-27-generic) |

**Alcance:** ASUS ProArt PX13 (HN7306EAC), AMD ACP70, 2× TAS2783 @ SoundWire.

---

## Relación con [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix)

| Proyecto | Enfoque |
|----------|---------|
| **brainchillz** | Etapa 1 — firmware, UCM, systemd boot/resume |
| **snd_repair** | Etapa 2+ — bugs kernel (A/B/C), **fix resume W1+W2**, upstream |

**Ambos son necesarios:** brainchillz solo no arregla resume a nivel kernel; snd_repair solo falla sin firmware.

---

## Producción vs laboratorio

**Recomendado:**

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh   # series A+B+C
sudo ./scripts/build-w1-w2.sh      # resume
sudo reboot
```

| Serie / capa | Problema | Módulos |
|--------------|----------|---------|
| A | Capture -22 | `snd-soc-tas2783-sdw` |
| B | FW timeout -110 (experimental) | `snd-soc-tas2783-sdw` |
| C | Estéreo L/R | `snd-soc-tas2783-sdw` + `snd-soc-sdw-utils` |
| W1 | Re-attach SoundWire tras resume | `soundwire-amd` |
| W2 | Recarga FW TAS2783 tras resume | `snd-soc-tas2783-sdw` |

**Laboratorio:** `patches/0001–0009` con trazas `ENZOPLAY` — solo para reproducir investigación.

---

## Documentación

| Doc | Contenido |
|-----|-----------|
| [`docs/es/INSTALACION.md`](docs/es/INSTALACION.md) | Instalación completa |
| [`docs/es/VERIFICACION.md`](docs/es/VERIFICACION.md) | Checklist |
| [`docs/es/ACTUALIZACION-KERNEL.md`](docs/es/ACTUALIZACION-KERNEL.md) | Tras `apt upgrade` |
| [`docs/es/ESTADO-PROYECTO.md`](docs/es/ESTADO-PROYECTO.md) | Estado del proyecto |
| [`docs/es/README.md`](docs/es/README.md) | Índice completo |

**Firmware:** binarios propietarios; no incluidos. Ver [`docs/es/01-instalacion-firmware.md`](docs/es/01-instalacion-firmware.md).

---

*Julio 2026 — ASUS ProArt PX13*
