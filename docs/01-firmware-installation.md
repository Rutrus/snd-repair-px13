# Stage 1 — ASUS firmware installation

> **English** | [Español](es/01-instalacion-firmware.md)

Built-in speakers on the ProArt PX13 require **proprietary TAS2783 calibration firmware** (`1714-1-8.bin`, `1714-1-B.bin`) that Linux does not ship. They are embedded in the official ASUS SmartAmp installer.

**Legal:** firmware files are not redistributed in this repository. Obtain them from the official ASUS driver.

This stage must complete **before** kernel patches (Stage 2).

---

## Overview

| Step | Action |
|------|--------|
| 1 | Clone the community firmware repo or follow the script below |
| 2 | Install `wine`, `rsync`, `curl` |
| 3 | Extract `.bin` files from the ASUS `.exe` with Wine |
| 4 | Copy to `/usr/lib/firmware/` and run `fix-px13-audio.sh` |
| 5 | Verify with `dmesg` / `wpctl` |

Reference: [brainchillz/asus-proart-px13-linux-speaker-fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix)

---

## Extraction script

```bash
#!/usr/bin/env bash
set -euo pipefail

WORK=/tmp/px13-tas2783
URL="https://dlcdnets.asus.com/pub/ASUS/nb/Image/Driver/Audio/47519/SmartAMP_TI_DCH_TexasInstruments_Z_V6.3.1.15_47519.exe?model=HN7306EAC"
TARGET_DIR="$(pwd)/firmware"

echo "==> [1/6] Cleaning previous artifacts..."
rm -f "$TARGET_DIR"/1714-1-*.bin
rm -rf "$WORK" && mkdir -p "$WORK" "$TARGET_DIR" && cd "$WORK"

echo "==> [2/6] Downloading official ASUS TI SmartAmp driver..."
curl -fL -A "Mozilla/5.0" -o smartamp.exe "$URL"
[ ! -s smartamp.exe ] && { echo "Download empty or failed"; exit 1; }

echo "==> [3/6] Initializing Wine environment..."
export WINEPREFIX="$WORK/wineprefix" WINEDEBUG=-all
wineboot -i >/dev/null 2>&1 || true

echo "==> [4/6] Async extraction from InstallAware temp..."
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

echo "==> [5/6] Locating extracted files..."
SRC=$(find "$WORK/snapshot" -name "1714-1-0x8.bin" | head -1)
if [ -z "$SRC" ]; then
    echo "ERROR: Files not found in Wine snapshot."
    exit 1
fi
SRC_DIR=$(dirname "$SRC")

echo "==> [6/6] Validating firmware size..."
if [ ! -s "$SRC_DIR/1714-1-0x8.bin" ] || [ ! -s "$SRC_DIR/1714-1-0xB.bin" ]; then
    echo "CRITICAL: Captured files are empty (0 bytes). Re-run the script."
    exit 1
fi

cp "$SRC_DIR/1714-1-0x8.bin" "$TARGET_DIR/1714-1-8.bin"
cp "$SRC_DIR/1714-1-0xB.bin" "$TARGET_DIR/1714-1-B.bin"

SIZE_8=$(stat -c%s "$TARGET_DIR/1714-1-8.bin")
SIZE_B=$(stat -c%s "$TARGET_DIR/1714-1-B.bin")

if [ "$SIZE_8" -lt 1000 ] || [ "$SIZE_B" -lt 1000 ]; then
    echo "ERROR: Firmware corrupt or too small ($SIZE_8 / $SIZE_B bytes)."
    exit 1
fi

echo "Firmware extracted successfully in $TARGET_DIR"
ls -lh "$TARGET_DIR"/*.bin
```

---

## Deploy to system

```bash
sudo apt update && sudo apt install -y wine rsync curl
# run extraction script above, then:
sudo cp firmware/1714-1-*.bin /usr/lib/firmware/
sudo ./fix-px13-audio.sh
```

---

## Verification

```bash
journalctl -k -b 0 | grep -i tas2783
# should NOT show: error playback without fw download

wpctl status
```

---

## Next step

Stage 2 — kernel patches:

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
sudo reboot
```
