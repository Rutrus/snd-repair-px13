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

# pci-ps may import snd_repair_phase7_t_mgr_reset_ms from soundwire-amd (phase7 correlate).
kernel_pci_ps_needs_amd_symvers() {
	[[ -f "${1:-$KERNEL_SRC}/sound/soc/amd/ps/pci-ps.c" ]] &&
		grep -q 'snd_repair_phase7_t_mgr_reset_ms' \
			"${1:-$KERNEL_SRC}/sound/soc/amd/ps/pci-ps.c" 2>/dev/null
}

kernel_amd_symvers_has_phase7_export() {
	local symvers="${1:-${KERNEL_SRC}/drivers/soundwire/Module.symvers}"
	[[ -f "$symvers" ]] &&
		grep -q 'snd_repair_phase7_t_mgr_reset_ms' "$symvers" 2>/dev/null
}

# Build snd-pci-ps.ko; pass KBUILD_EXTRA_SYMBOLS when correlate import is present.
kernel_make_pci_ps_modules() {
	local src="${KERNEL_SRC:?}"
	local build="${KERNEL_BUILD:?}"
	local ps_make_args=(M="${src}/sound/soc/amd/ps" CONFIG_SND_SOC_AMD_PS=m modules)

	if kernel_pci_ps_needs_amd_symvers "$src"; then
		local symvers="${src}/drivers/soundwire/Module.symvers"
		if kernel_amd_symvers_has_phase7_export "$symvers"; then
			ps_make_args+=(KBUILD_EXTRA_SYMBOLS="$symvers")
		else
			echo "ERROR: pci-ps imports snd_repair_phase7_t_mgr_reset_ms but $symvers lacks it" >&2
			echo "  Build soundwire-amd after phase7 correlate, or use PHASE6_SKIP_BUILD=1 from build-phase7.sh" >&2
			return 1
		fi
	fi
	make -C "$build" "${ps_make_args[@]}"
}
