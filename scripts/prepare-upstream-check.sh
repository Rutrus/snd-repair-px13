#!/usr/bin/env bash
# Verifica que los parches upstream aplican (requiere árbol git limpio).
# Uso: prepare-upstream-check.sh /ruta/a/linux-git
set -euo pipefail

KERNEL="${1:?Usage: $0 /path/to/linux-git-clone}"

[[ -d "$KERNEL/.git" ]] || { echo "Error: $KERNEL no es un clon git"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

apply_series() {
	local name="$1"
	shift
	local patches=("$@")
	echo "=== $name ==="
	(
		cd "$KERNEL"
		git checkout -q HEAD -- . 2>/dev/null || true
		git am --abort 2>/dev/null || true
		for p in "${patches[@]}"; do
			echo "  git am $(basename "$p")"
			git am "$p"
		done
		git reset --hard HEAD~$((${#patches[@]})) >/dev/null
	)
	echo "  OK"
}

apply_series "series-A" "$ROOT/upstream/series-A-capture/"*.patch
apply_series "series-C" "$ROOT/upstream/series-C-channel-map/"*.patch
# Serie B: descomentar tras VALIDATION-TODO
# apply_series "series-B" "$ROOT/upstream/series-B-firmware/"*.patch

echo "Todas las series comprobadas con git am."

