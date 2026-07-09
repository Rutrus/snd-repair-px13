# Etapa 1 — Instalación de firmware ASUS

> [English](../01-firmware-installation.md) | **Español**

Los altavoces integrados del ProArt PX13 requieren **firmware de calibración propietario TAS2783** (`1714-1-8.bin`, `1714-1-B.bin`) que Linux no incluye. Está embebido en el instalador oficial ASUS SmartAmp.

**Legal:** este repositorio no redistribuye los binarios. Obtenerlos del driver oficial ASUS.

Completar esta etapa **antes** de los parches del kernel (etapa 2).

---

## Resumen

| Paso | Acción |
|------|--------|
| 1 | Clonar el repo comunitario o usar el script siguiente |
| 2 | Instalar `wine`, `rsync`, `curl` |
| 3 | Extraer `.bin` del `.exe` ASUS con Wine |
| 4 | Copiar a `/usr/lib/firmware/` y ejecutar `fix-px13-audio.sh` |
| 5 | Verificar con `dmesg` / `wpctl` |

Referencia: [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix)

---

## Script de extracción

```bash
#!/usr/bin/env bash
set -euo pipefail

WORK=/tmp/px13-tas2783
URL="https://dlcdnets.asus.com/pub/ASUS/nb/Image/Driver/Audio/47519/SmartAMP_TI_DCH_TexasInstruments_Z_V6.3.1.15_47519.exe?model=HN7306EAC"
TARGET_DIR="$(pwd)/firmware"

echo "==> [1/6] Limpiando artefactos previos..."
rm -f "$TARGET_DIR"/1714-1-*.bin
rm -rf "$WORK" && mkdir -p "$WORK" "$TARGET_DIR" && cd "$WORK"

echo "==> [2/6] Descargando driver oficial ASUS TI SmartAmp..."
curl -fL -A "Mozilla/5.0" -o smartamp.exe "$URL"
[ ! -s smartamp.exe ] && { echo "Descarga vacía o fallida"; exit 1; }

echo "==> [3/6] Inicializando entorno Wine..."
export WINEPREFIX="$WORK/wineprefix" WINEDEBUG=-all
wineboot -i >/dev/null 2>&1 || true

echo "==> [4/6] Extracción asíncrona desde temp InstallAware..."
mkdir -p "$WORK/snapshot"
TEMP="$WINEPREFIX/drive_c/users/$USER/AppData/Local/Temp"

(
  while true; do
    for d in "$TEMP"/is-*; do
      [ -d "$d" ] && rsync -a "$d/" "$WORK/snapshot/" 2>/dev/null
    done
    sleep 0.1
  done
) &
WATCHER=$!
trap 'kill $WATCHER 2>/dev/null || true' EXIT

wine "$WORK/smartamp.exe" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART 2>/dev/null
sleep 6
kill $WATCHER 2>/dev/null || true

echo "==> [5/6] Localizando ficheros extraídos..."
SRC=$(find "$WORK/snapshot" -name "1714-1-0x8.bin" | head -1)
if [ -z "$SRC" ]; then
    echo "ERROR: No se encontraron ficheros en el snapshot de Wine."
    exit 1
fi
SRC_DIR=$(dirname "$SRC")

echo "==> [6/6] Validando tamaño del firmware..."
if [ ! -s "$SRC_DIR/1714-1-0x8.bin" ] || [ ! -s "$SRC_DIR/1714-1-0xB.bin" ]; then
    echo "CRÍTICO: Ficheros vacíos (0 bytes). Reejecutar el script."
    exit 1
fi

cp "$SRC_DIR/1714-1-0x8.bin" "$TARGET_DIR/1714-1-8.bin"
cp "$SRC_DIR/1714-1-0xB.bin" "$TARGET_DIR/1714-1-B.bin"

SIZE_8=$(stat -c%s "$TARGET_DIR/1714-1-8.bin")
SIZE_B=$(stat -c%s "$TARGET_DIR/1714-1-B.bin")

if [ "$SIZE_8" -lt 1000 ] || [ "$SIZE_B" -lt 1000 ]; then
    echo "ERROR: Firmware corrupto o demasiado pequeño ($SIZE_8 / $SIZE_B bytes)."
    exit 1
fi

echo "Firmware extraído correctamente en $TARGET_DIR"
ls -lh "$TARGET_DIR"/*.bin
```

---

## Despliegue en el sistema

```bash
sudo apt update && sudo apt install -y wine rsync curl
sudo cp firmware/1714-1-*.bin /usr/lib/firmware/
sudo ./fix-px13-audio.sh
```

---

## Verificación

```bash
journalctl -k -b 0 | grep -i tas2783
wpctl status
```

---

## Siguiente paso

Etapa 2 — parches del kernel:

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
sudo reboot
```
