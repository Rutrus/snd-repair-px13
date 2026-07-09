#!/usr/bin/env bash
# Flujo guiado de validación Serie B (matriz 20–30 boots).
# Ejecutar tras cada boot; opcionalmente batería de rates y S3.
#
# Uso:
#   fw-validation-run.sh boot [--notes "..."]
#   fw-validation-run.sh boot-audio
#   fw-validation-run.sh suspend    # tras resume desde S3
#   fw-validation-run.sh rates      # 44100, 48000, 96000 (sin reinicio)
#   fw-validation-run.sh status     # muestra fw-summary.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COLLECT="${SCRIPT_DIR}/fw-validation-collect.sh"
ALSA_DEV="${ALSA_DEV:-plughw:1,2}"

cmd="${1:-boot}"
shift || true

case "$cmd" in
boot)
	"$COLLECT" "$@"
	;;
boot-audio)
	"$COLLECT" --audio "$@"
	;;
suspend)
	"$COLLECT" --suspend "$@"
	;;
rates)
	for rate in 44100 48000 96000; do
		echo "=== Rate ${rate} Hz ==="
		speaker-test -D "$ALSA_DEV" -r "$rate" -c 2 -t wav -l 1 -s 1 >/dev/null 2>&1 || true
		"$COLLECT" --rate "$rate" --notes "rate-test ${rate}" "$@"
	done
	;;
status)
	VAL_DIR="${VAL_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)/validation}"
	cat "${VAL_DIR}/fw-summary.md" 2>/dev/null || echo "Sin datos — ejecuta fw-validation-run.sh boot"
	;;
*)
	echo "Uso: $0 {boot|boot-audio|suspend|rates|status} [opciones collect]" >&2
	exit 1
	;;
esac
