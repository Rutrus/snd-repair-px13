#!/usr/bin/env bash
# Descarga y prepara el árbol de fuentes del kernel en ejecución.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

KVER="$(uname -r)"
BUILD_DIR="$REPO_ROOT/build"
SRC="$KERNEL_SRC"

echo "==> Kernel: $KVER"
echo "==> Destino: $SRC"

sudo apt-get update
sudo apt-get install -y \
	build-essential flex bison libssl-dev libelf-dev dwarves bc zstd \
	"linux-headers-$KVER"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -d "$SRC/.git" && ! -f "$SRC/Makefile" ]]; then
	PKG="linux-source-${KVER%%-*}"
	if ! dpkg -l "$PKG" &>/dev/null; then
		echo "==> Instalando paquete de fuentes: $PKG"
		sudo apt-get install -y "$PKG" || {
			echo "Paquete $PKG no disponible. Prueba: apt-cache search linux-source" >&2
			exit 1
		}
	fi
	DEB="$(dpkg -L "$PKG" 2>/dev/null | grep -E '\.tar\.(bz2|xz)$' | head -1)"
	if [[ -z "$DEB" ]]; then
		DEB="$(ls "$BUILD_DIR"/linux-source-*.tar.* 2>/dev/null | head -1)"
	fi
	if [[ -n "$DEB" && -f "$DEB" ]]; then
		echo "==> Extrayendo $DEB"
		tar -xf "$DEB" -C "$BUILD_DIR"
		EXTRACTED="$(find "$BUILD_DIR" -maxdepth 1 -type d -name 'linux-source-*' | head -1)"
		[[ -n "$EXTRACTED" ]] && ln -sfn "$(basename "$EXTRACTED")" "$(basename "$SRC")"
	fi
fi

if [[ ! -f "$SRC/Makefile" ]]; then
	echo "No se encontró árbol en $SRC. Extrae manualmente linux-source o clona git." >&2
	exit 1
fi

cd "$SRC"
if [[ ! -f .config ]]; then
	cp "/boot/config-$KVER" .config
	make olddefconfig
fi
make modules_prepare

echo "==> Árbol listo: $SRC"
echo "    Siguiente: $SCRIPTS/apply-production-patches.sh"
