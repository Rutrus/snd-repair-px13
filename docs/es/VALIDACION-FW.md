# Matriz de validación de firmware — guía

> [English](../FW-VALIDATION.md) | **Español**

Recopilar datos **reproducibles por boot** para el **Problema B** (firmware TAS2783 `-110` intermitente) y detectar regresiones tras parches de kernel.

**Objetivo:** 20–30 arranques en frío antes de promover la Serie B a upstream. Ver `[../../upstream/series-B-firmware/VALIDATION-TODO.md](../../upstream/series-B-firmware/VALIDATION-TODO.md)`.

---

## Qué se registra

Cada boot añade una fila a `validation/fw-matrix.csv` y archiva el log kernel en `validation/boot-logs/`.


| Campo                        | Significado                                                                        |
| ---------------------------- | ---------------------------------------------------------------------------------- |
| `uid8_fw` / `uidb_fw`        | Carga FW amp izquierdo (`0x8`) / derecho (`0xb`): `OK`, `WARN`, `FAIL110`, `FAIL?` |
| `regression_capture`         | `YES` si regresión Serie A (capture/transporte)                                    |
| `left_audio` / `right_audio` | Solo con `--audio` (manual, interactivo)                                           |
| `notes`                      | Texto libre: `auto@boot`, parches, etc.                                            |


Resumen: `validation/fw-summary.md`.

---



## Opción A — Logging automático (recomendado)



### 1. Instalar la unidad system

**Servicio de usuario** (por defecto, sin sudo):

```bash
cd ~/snd_repair
./scripts/install-fw-validation-service.sh
```

**Servicio de sistema** (sin necesidad de login):

```bash
sudo ./scripts/install-fw-validation-service.sh --system
```



### 2. Activar linger (solo servicio usuario)

Para registrar en cada reboot **sin iniciar sesión**:

```bash
sudo loginctl enable-linger "$USER"
```



### 3. Flujo

**Boot:** login/linger → espera 25s → `auto@boot`

**Suspend:** tras `px13-audio-resume` (drop-in, background, no bloquea).

```bash
sudo ./scripts/install-fw-validation-service.sh --suspend-only
```

### Bloqueo en resume

Si el equipo se congela al despertar:

```bash
journalctl -b -1 | grep -iE 'px13-audio|soft lockup|unbind failed'
```

Secuencia típica: `unbind failed/timed out` en PCI ACP → soft lockup → reboot forzado. Es **px13-audio-resume** (brainchillz), no el script de validación. El hook ahora corre **después** de px13 y en background.

---

### 4. Comprobar

```bash
systemctl --user status snd-repair-fw-validation-suspend.service
journalctl --user -u snd-repair-fw-validation-suspend.service -b
```



### 5. Desinstalar

```bash
./scripts/install-fw-validation-service.sh --remove
```

---



## Opción B — Manual

Tras cada reboot:

```bash
./scripts/fw-validation-run.sh boot
./scripts/fw-validation-run.sh boot --notes "prueba Serie B"
```

Con prueba estéreo interactiva:

```bash
./scripts/fw-validation-run.sh boot-audio
```

Tras suspend/resume:

```bash
./scripts/fw-validation-run.sh suspend
```

Forzar segundo registro del mismo boot:

```bash
./scripts/fw-validation-collect.sh --force --notes "repetir"
```

---



## Leer resultados

```bash
cat validation/fw-summary.md
less validation/boot-logs/boot-003.log
```


| `uid*_fw` | Significado                             |
| --------- | --------------------------------------- |
| `OK`      | Sin fallo FW en dmesg                   |
| `WARN`    | `playback without fw`                   |
| `FAIL110` | `FW download failed: -110` (Problema B) |


---



## Archivos


| Ruta                                       | Función                                                  |
| ------------------------------------------ | -------------------------------------------------------- |
| `scripts/fw-validation-collect.sh`         | Colector principal                                       |
| `scripts/fw-validation-run.sh`             | CLI (`boot`, `boot-audio`, `suspend`, `rates`, `status`) |
| `scripts/fw-validation-boot-hook.sh`       | Espera + collect (systemd)                               |
| `scripts/install-fw-validation-service.sh` | Instalar/desinstalar                                     |
| `systemd/snd-repair-fw-validation.service` | Plantilla de unidad                                      |


Variables: `SND_REPAIR_FW_DELAY` (default 25s), `VAL_DIR`, `ALSA_DEV`.

---



## Relación con el fix completo


| Capa                     | Dónde                     |
| ------------------------ | ------------------------- |
| Firmware + UCM + suspend | brainchillz (etapa 1)     |
| Parches kernel A/B/C     | snd_repair (etapa 2)      |
| **Matriz de validación** | esta guía + `validation/` |


No sustituye `[VERIFICACION.md](VERIFICACION.md)`; construye una **base de datos de boots** para estadísticas Serie B.

---



## Problemas frecuentes


| Síntoma                    | Solución                                |
| -------------------------- | --------------------------------------- |
| Sin fila nueva tras reboot | `loginctl enable-linger` o `--system`   |
| Servicio `inactive (dead)` tras boot | Normal hasta el primer suspend | Suspende; luego `journalctl -u snd-repair-fw-validation-suspend -b` |
| Unidad suspend no corre | Unidad antigua con `DefaultDependencies=no` | `sudo ./scripts/install-fw-validation-service.sh --suspend-only` |
| Fila omitida               | Mismo boot ya registrado; `--force`     |
| Permiso en CSV             | `chown -R $USER validation/`            |


---



## Docs relacionados

- `[../../validation/README.es.md](../../validation/README.es.md)`
- `[../../upstream/series-B-firmware/VALIDATION-TODO.md](../../upstream/series-B-firmware/VALIDATION-TODO.md)`
- `[analisis-fw.md](analisis-fw.md)`
- `[INSTALACION.md](INSTALACION.md)`

