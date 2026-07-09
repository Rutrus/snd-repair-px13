#!/usr/bin/env bash
# Hook de arranque: espera a que el kernel cargue FW TAS2783 y registra el boot.
# Invocado por systemd (snd-repair-fw-validation.service).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
COLLECT="${REPO}/scripts/fw-validation-collect.sh"
DELAY="${SND_REPAIR_FW_DELAY:-25}"

if [[ ! -x "$COLLECT" ]]; then
	echo "No existe $COLLECT" >&2
	exit 1
fi

echo "snd_repair: esperando ${DELAY}s antes de registrar boot (FW TAS2783)..."
sleep "$DELAY"

exec "$COLLECT" --notes "auto@boot"
