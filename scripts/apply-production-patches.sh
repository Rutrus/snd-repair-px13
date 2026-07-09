#!/usr/bin/env bash
# Apply local production patches (0004+0006+0007+0009). Patch 0009 includes ENZOPLAY
# debug traces — for clean modules use build-from-upstream.sh instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
STAMP="$SRC/.snd-repair-production-applied"
KVER_STAMP="$SRC/.snd-repair-kernel-version"
KVER="$(uname -r)"

if [[ ! -f "$SRC/Makefile" ]]; then
	echo "Ejecuta primero: $SCRIPT_DIR/prepare-kernel-tree.sh" >&2
	exit 1
fi

cd "$SRC"

if [[ -f "$KVER_STAMP" && "$(cat "$KVER_STAMP")" != "$KVER" ]]; then
	echo "==> Kernel cambió ($(cat "$KVER_STAMP") → $KVER); reseteando árbol parcheado"
	rm -f "$STAMP"
	find sound/soc/codecs sound/soc/sdw_utils -name '*.rej' -delete 2>/dev/null || true
fi

if [[ -f "$STAMP" ]]; then
	echo "Parches de producción ya aplicados ($(cat "$STAMP")). Para re-aplicar:"
	echo "  rm -f $STAMP $KVER_STAMP && git -C $SRC checkout -- sound/ 2>/dev/null || true"
	exit 0
fi

echo "==> Aplicando parches de producción en $SRC"
while IFS= read -r patch; do
	echo "    $patch"
	patch -p1 --forward < "$PATCHES/$patch" || {
		echo "Fallo al aplicar $patch (¿ya aplicado?)" >&2
		exit 1
	}
done < <(production_patches)

date -Is >"$STAMP"
echo "$KVER" >"$KVER_STAMP"
echo "==> Listo. Compilar con: $SCRIPT_DIR/build-production-modules.sh"
