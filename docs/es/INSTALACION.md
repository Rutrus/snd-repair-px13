# Guía de instalación completa — ASUS ProArt PX13

> [English](../INSTALL.md) | **Español**

Procedimiento de extremo a extremo: **capa de usuario** (firmware, UCM, PipeWire) + **parches de kernel** (este repo).

**Probado:** Ubuntu 26.04 / Linux Mint 22.x, kernel `7.0.0-27-generic`, ProArt PX13 HN7306EAC.

---

## Panorama

| Etapa | Repositorio | Qué corrige |
|-------|-------------|-------------|
| **1a** | [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) | Firmware propietario + UCM ALSA + suspend/resume |
| **1b** | Este repo (`snd_repair`) | Bugs del driver kernel (capture -22, FW -110, estéreo L/R) |

La etapa 1 sola puede dar audio parcial o inestable. La etapa 2 sola falla sin firmware. **Usar ambas.**

---

## Requisitos

Ver [`PREREQUISITOS.md`](PREREQUISITOS.md).

---

## Etapa 1 — brainchillz (firmware + UCM + systemd)

```bash
git clone https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix.git
cd asus-proart-px13-linux-speaker-fix
```

### 1. Extraer firmware (una vez)

Seguir `firmware/EXTRACT-FIRMWARE.md` en ese repo, o [`01-instalacion-firmware.md`](01-instalacion-firmware.md).

Ficheros necesarios localmente (no en git):

```text
firmware/1714-1-8.bin   (~40 KB)
firmware/1714-1-B.bin     (~40 KB)
```

### 2. Instalador de capa de usuario

```bash
./fix-px13-audio.sh
```

Instala:

| Componente | Función |
|------------|---------|
| Firmware → `/lib/firmware/` | Carga de calibración TAS2783 |
| Perfil UCM `tas2783.conf` | PipeWire ve **Speaker** interno |
| Parche `rt721.conf` | Corrige verbo HiFi |
| `px13-audio-rebind.service` | Reset PCI ACP al **arranque** |
| `px13-audio-resume.service` | Reset PCI ACP tras **suspend/resume** |

### 3. Reiniciar

```bash
sudo reboot
```

### 4. Comprobación rápida (etapa 1)

```bash
journalctl -k -b 0 | grep -i tas2783
wpctl status
```

Si solo aparece **Dummy Output**, la etapa 1 no terminó bien — no pasar a la etapa 2.

---

## Etapa 2 — snd_repair (módulos kernel)

```bash
cd /ruta/a/snd_repair
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
sudo reboot
```

Aplica series upstream **A + B + C** (sin trazas `ENZOPLAY`) e instala `snd-soc-tas2783-sdw.ko` y `snd-soc-sdw-utils.ko`.

**Nota:** Serie B (retry FW `-110`) es **experimental** (RFC).

---

## Verificación final

Ver [`VERIFICACION.md`](VERIFICACION.md).

Mínimo:

```bash
journalctl -k -b 0 | grep -i tas2783
wpctl status
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

### Prueba suspend (systemd etapa 1)

```bash
systemctl suspend
wpctl status
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

---

## Tras actualizar el kernel

```bash
./scripts/post-kernel-update.sh
sudo reboot
```

Ver [`ACTUALIZACION-KERNEL.md`](ACTUALIZACION-KERNEL.md).

---

## Reversión

[`REVERSION.md`](REVERSION.md)

---

## Resolución de problemas

| Síntoma | Causa probable | Acción |
|---------|----------------|--------|
| Solo Dummy Output | Etapa 1 incompleta | Reejecutar `fix-px13-audio.sh` |
| `error playback without fw download` | Sin firmware | Instalar `.bin` |
| Solo altavoz izquierdo | Falta etapa 2 | `build-from-upstream.sh` + reboot |
| Sin audio tras suspend | Servicio resume | Revisar `px13-audio-resume.service` |
| `-110` en algunos boots | Race FW (Serie B) | Reboot; ampliar matriz |
| vermagic incorrecto | Módulos viejos | `post-kernel-update.sh` |

Plantilla de issue: [bug report](../../.github/ISSUE_TEMPLATE/bug_report.md).
