#!/usr/bin/env bash
# Instala logging automático: boot (user/system) + suspend (drop-in en px13-audio-resume).
#
# Uso:
#   ./scripts/install-fw-validation-service.sh
#   sudo ./scripts/install-fw-validation-service.sh --system
#   ./scripts/install-fw-validation-service.sh --remove
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT_BOOT="snd-repair-fw-validation.service"
UNIT_SUSPEND_OLD="snd-repair-fw-validation-suspend.service"
DROPIN_DIR="/etc/systemd/system/px13-audio-resume.service.d"
DROPIN_NAME="snd-repair-fw-validation.conf"
DROPIN_TEMPLATE="${REPO}/systemd/px13-audio-resume.service.d-snd-repair-fw-validation.conf"
RUN_USER="${SUDO_USER:-${USER}}"
REMOVE=0
SCOPE="user"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--system)        SCOPE="system"; shift ;;
	--user)          SCOPE="user"; shift ;;
	--remove|--uninstall) REMOVE=1; shift ;;
	--suspend-only)  SCOPE="suspend-only"; shift ;;
	-h|--help)
		sed -n '3,8p' "$0"
		exit 0
		;;
	*) echo "Opción desconocida: $1" >&2; exit 1 ;;
	esac
done

chmod +x "${REPO}/scripts/fw-validation-boot-hook.sh" \
	"${REPO}/scripts/fw-validation-suspend-hook.sh" \
	"${REPO}/scripts/fw-validation-collect.sh" \
	"${REPO}/scripts/px13-audio-fix.sh" \
	"${REPO}/scripts/install-px13-audio-fix.sh" \
	"${REPO}/scripts/px13-restore-pipewire.sh"

render_unit() {
	local template="$1"
	local scope="$2"
	if [[ "$scope" == "system" ]]; then
		sed \
			-e "s|@REPO_ROOT@|${REPO}|g" \
			-e "s|@RUN_USER@|${RUN_USER}|g" \
			-e '/^\[Service\]/a User=@RUN_USER@\nGroup=@RUN_USER@' \
			-e 's|WantedBy=default.target|WantedBy=multi-user.target|' \
			"$template" | sed "s|@RUN_USER@|${RUN_USER}|g"
	else
		sed \
			-e "s|@REPO_ROOT@|${REPO}|g" \
			-e "s|@RUN_USER@|${RUN_USER}|g" \
			"$template"
	fi
}

install_suspend_dropin() {
	[[ "$(id -u)" -eq 0 ]] || { echo "Suspend drop-in requiere sudo." >&2; exit 1; }
	mkdir -p "$DROPIN_DIR"
	sed "s|@REPO_ROOT@|${REPO}|g" "$DROPIN_TEMPLATE" >"${DROPIN_DIR}/${DROPIN_NAME}"
	# Retirar unidad antigua (suspend.target) — causaba carrera con px13-audio-resume
	systemctl disable --now "$UNIT_SUSPEND_OLD" 2>/dev/null || true
	rm -f "/etc/systemd/system/${UNIT_SUSPEND_OLD}"
	rm -f "${HOME}/.config/systemd/user/${UNIT_SUSPEND_OLD}" 2>/dev/null || true
	systemctl daemon-reload
	echo "Suspend: ${DROPIN_DIR}/${DROPIN_NAME} (ExecStartPost tras px13-audio-resume)"
}

remove_all() {
	systemctl --user disable --now "$UNIT_BOOT" 2>/dev/null || true
	rm -f "${HOME}/.config/systemd/user/${UNIT_BOOT}" 2>/dev/null || true
	systemctl --user daemon-reload 2>/dev/null || true
	if [[ "$(id -u)" -eq 0 ]]; then
		systemctl disable --now "$UNIT_BOOT" "$UNIT_SUSPEND_OLD" 2>/dev/null || true
		rm -f "/etc/systemd/system/${UNIT_BOOT}" "/etc/systemd/system/${UNIT_SUSPEND_OLD}"
		rm -f "${DROPIN_DIR}/${DROPIN_NAME}"
		rmdir "$DROPIN_DIR" 2>/dev/null || true
		systemctl daemon-reload
	else
		sudo rm -f "${DROPIN_DIR}/${DROPIN_NAME}" 2>/dev/null || true
		sudo systemctl disable --now "$UNIT_SUSPEND_OLD" 2>/dev/null || true
		sudo rm -f "/etc/systemd/system/${UNIT_SUSPEND_OLD}" 2>/dev/null || true
		sudo systemctl daemon-reload 2>/dev/null || true
	fi
	echo "Desinstalado: boot + suspend drop-in"
}

if [[ "$REMOVE" -eq 1 ]]; then
	remove_all
	exit 0
fi

if [[ "$SCOPE" == "suspend-only" ]]; then
	install_suspend_dropin
	exit 0
fi

install_boot() {
	local scope="$1"
	if [[ "$scope" == "system" ]]; then
		[[ "$(id -u)" -eq 0 ]] || { echo "Usa: sudo $0 --system" >&2; exit 1; }
		render_unit "${REPO}/systemd/${UNIT_BOOT}" system \
			>/etc/systemd/system/${UNIT_BOOT}
		systemctl daemon-reload
		systemctl enable "${UNIT_BOOT}"
		echo "Boot (system): /etc/systemd/system/${UNIT_BOOT}"
	else
		local dir="${HOME}/.config/systemd/user"
		mkdir -p "$dir"
		render_unit "${REPO}/systemd/${UNIT_BOOT}" user >"${dir}/${UNIT_BOOT}"
		systemctl --user daemon-reload
		systemctl --user enable "${UNIT_BOOT}"
		echo "Boot (user): ${dir}/${UNIT_BOOT}"
	fi
}

if [[ "$SCOPE" == "system" ]]; then
	install_boot system
	install_suspend_dropin
	exit 0
fi

install_boot user
echo ""
echo "Instalando suspend (drop-in en px13-audio-resume)..."
if [[ "$(id -u)" -eq 0 ]]; then
	install_suspend_dropin
else
	sudo "$0" --suspend-only
fi

if loginctl show-user "$RUN_USER" -p Linger 2>/dev/null | grep -q 'Linger=no'; then
	echo ""
	echo "Boot sin login: sudo loginctl enable-linger ${RUN_USER}"
fi

echo ""
echo "Boot    → tras login (~25s), user unit"
echo "Suspend → tras px13-audio-resume, en background (~25s extra)"
echo "Log hook: ${REPO}/validation/.state/suspend-hook.log"
