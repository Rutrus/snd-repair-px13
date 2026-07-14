# shellcheck shell=bash
# Rutas comunes del repositorio snd_repair.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCHES="${REPO_ROOT}/patches"
SCRIPTS="${REPO_ROOT}/scripts"
KVER="${KVER:-$(uname -r)}"
KERNEL_BUILD="${KERNEL_BUILD:-/lib/modules/$KVER/build}"
if [[ -z "${KERNEL_SRC:-}" ]]; then
	if [[ -d "$REPO_ROOT/build/linux-source" ]]; then
		KERNEL_SRC="$REPO_ROOT/build/linux-source"
	elif compgen -G "$REPO_ROOT/linux-source-*" >/dev/null 2>&1; then
		KERNEL_SRC="$(ls -d "$REPO_ROOT"/linux-source-* 2>/dev/null | head -1)"
	else
		KERNEL_SRC="$REPO_ROOT/build/linux-source"
	fi
fi

UPSTREAM="${REPO_ROOT}/upstream"

production_patches() {
	echo "0004-tas2783-skip-capture-without-source-ports.patch"
	echo "0006-tas2783-fw-retry-on-timeout.patch"
	echo "0007-tas2783-hw-params-wait-fw.patch"
	echo "0009-stereo-ch-map-split.patch"
}

# Clean patches for daily use (no ENZOPLAY / ENZODBG). GPL-2.0-only when applied to Linux.
upstream_patch_files() {
	find "$UPSTREAM/series-A-capture" -maxdepth 1 -name '*.patch' 2>/dev/null | sort
	find "$UPSTREAM/series-B-firmware" -maxdepth 1 -name '*.patch' 2>/dev/null | sort
	find "$UPSTREAM/series-C-channel-map" -maxdepth 1 -name '*.patch' 2>/dev/null | sort
}

# Fix ownership after mixed sudo/user builds (make writes .o/.ko in-tree).
ensure_kernel_tree_writable() {
	local src="${1:-$KERNEL_SRC}"
	local user group d
	[[ -d "$src" ]] || return 0
	if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
		user="$SUDO_USER"
		group="$(id -gn "$SUDO_USER")"
	else
		user="$(id -un)"
		group="$(id -gn)"
	fi
	local -a dirs=(
		"$src/sound/soc/codecs"
		"$src/sound/soc/sdw_utils"
		"$src/drivers/soundwire"
		"$src/sound/soc/amd/ps"
	)
	for d in "${dirs[@]}"; do
		[[ -d "$d" ]] || continue
		if [[ $EUID -eq 0 ]]; then
			if find "$d" -maxdepth 2 ! -user "$user" -print -quit 2>/dev/null | grep -q .; then
				echo "==> Fixing kernel tree ownership: $d -> $user:$group"
				chown -R "$user:$group" "$d"
			fi
		elif [[ ! -O "$d" ]]; then
			echo "==> Fixing kernel tree ownership: $d (not owned by $user — prior sudo build?)"
			sudo chown -R "$user:$group" "$d"
		fi
	done
	if compgen -G "$src/.snd-repair-*" >/dev/null 2>&1; then
		local stamp
		for stamp in "$src"/.snd-repair-*; do
			[[ -O "$stamp" ]] || sudo chown "$user:$group" "$stamp" 2>/dev/null || true
		done
	fi
}
