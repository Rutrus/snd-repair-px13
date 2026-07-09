#!/usr/bin/env bash
# Instala scripts/px13-audio-fix.sh sobre brainchillz /usr/local/sbin/px13-audio-fix.sh
#
# Uso:
#   sudo ./scripts/install-px13-audio-fix.sh
#   sudo ./scripts/install-px13-audio-fix.sh --remove
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${SCRIPT_DIR}/px13-audio-fix.sh"
DEST="/usr/local/sbin/px13-audio-fix.sh"
BACKUP="/usr/local/sbin/px13-audio-fix.sh.brainchillz.bak"
REMOVE=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--remove|--uninstall) REMOVE=1; shift ;;
	-h|--help)
		sed -n '3,7p' "$0"
		exit 0
		;;
	*) echo "Opción desconocida: $1" >&2; exit 1 ;;
	esac
done

if [[ "$REMOVE" -eq 1 ]]; then
	if [[ -f "$BACKUP" ]]; then
		install -m 0755 "$BACKUP" "$DEST"
		rm -f "$BACKUP"
		echo "Restaurado brainchillz original → $DEST"
	else
		echo "Sin backup en $BACKUP — nada que restaurar" >&2
		exit 1
	fi
	rm -f /etc/default/px13-snd-repair
	rm -f "${DROPIN_DIR}/${DROPIN_NAME}"
	rmdir "$DROPIN_DIR" 2>/dev/null || true
	systemctl daemon-reload 2>/dev/null || true
	exit 0
fi

[[ -f "$SRC" ]] || { echo "Falta $SRC" >&2; exit 1; }
chmod +x "$SRC"

if [[ -f "$DEST" && ! -f "$BACKUP" ]]; then
	cp -a "$DEST" "$BACKUP"
	echo "Backup → $BACKUP"
fi

install -m 0755 "$SRC" "$DEST"

REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULTS="/etc/default/px13-snd-repair"
DROPIN_DIR="/etc/systemd/system/px13-audio-rebind.service.d"
DROPIN_NAME="snd-repair.conf"
DROPIN_SRC="${SCRIPT_DIR}/../systemd/px13-audio-rebind.service.d-snd-repair.conf"
cat >"$DEFAULTS" <<EOF
# snd_repair paths (installed by install-px13-audio-fix.sh)
SND_REPAIR_REPO=${REPO}
PX13_RUN_USER=${SUDO_USER:-${USER}}
# No pink noise on boot/resume; cold boot skips PCI reset (see BOOT-INCIDENT-2026-07-09)
PX13_SKIP_SPEAKER_TEST=1
PX13_SKIP_PCI_ON_BOOT=1
EOF
chmod 644 "$DEFAULTS"

mkdir -p "$DROPIN_DIR"
install -m 0644 "$DROPIN_SRC" "${DROPIN_DIR}/${DROPIN_NAME}"
systemctl daemon-reload

echo "Instalado snd_repair px13-audio-fix → $DEST"
echo "Defaults → $DEFAULTS"
echo "Drop-in → ${DROPIN_DIR}/${DROPIN_NAME}"
echo "  PX13_SKIP_SPEAKER_TEST=1  PX13_SKIP_PCI_ON_BOOT=1"
echo "Ejecutar: sudo systemctl restart px13-audio-rebind.service  # prueba sin reboot"
