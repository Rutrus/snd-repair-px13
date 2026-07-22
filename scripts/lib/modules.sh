# shellcheck shell=bash
# Overlay install helpers: stage → /lib/modules/$KVER/updates/snd_repair/
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SND_REPAIR_OVERLAY_REL="updates/snd_repair"
SND_REPAIR_OVERLAY_DIR="/lib/modules/$KVER/$SND_REPAIR_OVERLAY_REL"
SND_REPAIR_STAGING_DIR="${SND_REPAIR_STAGING_DIR:-$REPO_ROOT/build/staging/$KVER}"
SND_REPAIR_STATE_DIR="${SND_REPAIR_STATE_DIR:-/var/lib/snd_repair}"
SND_REPAIR_DEPMOD_CONF="/etc/depmod.d/snd-repair.conf"

MARKER_0001='post-sleep playback fw_reinit failed'
MARKER_0001B='snd_repair post-resume fw_reinit'
MARKER_0002='amd_sdw_kick_irq_if_pending'
MARKER_0003='snd_repair resume enum kick'
MARKER_0003B='snd_repair resume enum kick delayed'

# basename.ko.zst → logical role
MODULE_TAS="snd-soc-tas2783-sdw.ko.zst"
MODULE_AMD="soundwire-amd.ko.zst"
MODULE_UTILS="snd-soc-sdw-utils.ko.zst"

INTREE_TAS="/lib/modules/$KVER/kernel/sound/soc/codecs/$MODULE_TAS"
INTREE_AMD="/lib/modules/$KVER/kernel/drivers/soundwire/$MODULE_AMD"
INTREE_UTILS="/lib/modules/$KVER/kernel/sound/soc/sdw_utils/$MODULE_UTILS"

# True when we can actually mutate system module/GRUB paths (not merely EUID=0 in a sandbox).
have_system_write() {
	local probe="${1:-/lib/modules}"
	[[ -w "$probe" ]]
}

require_root_or_print() {
	local cmd=("$@")
	if have_system_write /lib/modules; then
		return 0
	fi
	echo "Root required (system write). Run:" >&2
	echo "  sudo ${cmd[*]}" >&2
	return 1
}

ko_strings_has() {
	# Returns 0 if needle appears in module strings.
	# Must disable pipefail: grep -q exits early → strings gets SIGPIPE → false negative.
	local file="$1"
	local needle="$2"
	local rc
	[[ -f "$file" ]] || return 1
	set +o pipefail
	case "$file" in
	*.zst) zstdcat "$file" | strings | grep -Fq -- "$needle"; rc=$? ;;
	*) strings "$file" | grep -Fq -- "$needle"; rc=$? ;;
	esac
	set -o pipefail
	return "$rc"
}

resolve_mod_path() {
	# Prefer live modinfo path; fall back to overlay then in-tree.
	local modname="$1"
	local overlay_file="$2"
	local intree_file="$3"
	local p
	p="$(modinfo -n "$modname" 2>/dev/null || true)"
	if [[ -n "$p" && -f "$p" ]]; then
		printf '%s\n' "$p"
		return 0
	fi
	if [[ -f "$overlay_file" ]]; then
		printf '%s\n' "$overlay_file"
		return 0
	fi
	if [[ -f "$intree_file" ]]; then
		printf '%s\n' "$intree_file"
		return 0
	fi
	return 1
}

ensure_staging_dir() {
	mkdir -p "$SND_REPAIR_STAGING_DIR"
}

stage_ko() {
	# stage_ko <uncompressed.ko>  → build/staging/$KVER/<name>.ko.zst
	local ko="$1"
	local name
	[[ -f "$ko" ]] || {
		echo "Missing build artifact: $ko" >&2
		return 1
	}
	name="$(basename "$ko").zst"
	ensure_staging_dir
	zstd -19 -f "$ko" -o "$SND_REPAIR_STAGING_DIR/$name"
	echo "==> Staged $SND_REPAIR_STAGING_DIR/$name"
}

install_overlay_from_staging() {
	require_root_or_print "$REPO_ROOT/scripts/snd-repair" install-modules || return 1

	local -a needed=("$MODULE_TAS" "$MODULE_AMD" "$MODULE_UTILS")
	local f
	ensure_staging_dir
	for f in "${needed[@]}"; do
		[[ -f "$SND_REPAIR_STAGING_DIR/$f" ]] || {
			echo "Missing staged module: $SND_REPAIR_STAGING_DIR/$f" >&2
			echo "Run: $REPO_ROOT/scripts/snd-repair build" >&2
			return 1
		}
	done

	# Preflight markers on staged artifacts
	ko_strings_has "$SND_REPAIR_STAGING_DIR/$MODULE_TAS" "$MARKER_0001" || {
		echo "ERROR: staged $MODULE_TAS missing 0001 marker — rebuild post-sleep first" >&2
		return 1
	}
	ko_strings_has "$SND_REPAIR_STAGING_DIR/$MODULE_TAS" "$MARKER_0001B" || {
		echo "ERROR: staged $MODULE_TAS missing 0001b marker — rebuild with post-resume dual-trigger" >&2
		return 1
	}
	ko_strings_has "$SND_REPAIR_STAGING_DIR/$MODULE_AMD" "$MARKER_0002" || {
		echo "ERROR: staged $MODULE_AMD missing 0002 marker — rebuild amd resume first" >&2
		return 1
	}
	ko_strings_has "$SND_REPAIR_STAGING_DIR/$MODULE_AMD" "$MARKER_0003" || {
		echo "ERROR: staged $MODULE_AMD missing 0003 marker — rebuild with force-ping patch" >&2
		return 1
	}
	ko_strings_has "$SND_REPAIR_STAGING_DIR/$MODULE_AMD" "$MARKER_0003B" || {
		echo "ERROR: staged $MODULE_AMD missing 0003b marker — rebuild with delayed-kick patch" >&2
		return 1
	}

	mkdir -p "$SND_REPAIR_OVERLAY_DIR" "$SND_REPAIR_STATE_DIR"
	for f in "${needed[@]}"; do
		install -m 0644 "$SND_REPAIR_STAGING_DIR/$f" "$SND_REPAIR_OVERLAY_DIR/$f"
		echo "==> Installed $SND_REPAIR_OVERLAY_DIR/$f"
	done

	# Ensure updates/ is searched before built-in (idempotent; Ubuntu usually has this).
	if [[ ! -f "$SND_REPAIR_DEPMOD_CONF" ]]; then
		cat >"$SND_REPAIR_DEPMOD_CONF" <<'EOF'
# snd_repair — prefer overlay modules over in-tree stock
search updates built-in
EOF
		echo "==> Wrote $SND_REPAIR_DEPMOD_CONF"
	fi

	depmod -a "$KVER"

	{
		echo "kver=$KVER"
		echo "installed_at=$(date -Is)"
		echo "overlay=$SND_REPAIR_OVERLAY_DIR"
		echo "marker_0001=ok"
		echo "marker_0001b=ok"
		echo "marker_0002=ok"
		echo "marker_0003=ok"
		echo "marker_0003b=ok"
	} >"$SND_REPAIR_STATE_DIR/$KVER.state"

	echo ""
	echo "Overlay installed for $KVER. Reboot to load modules:"
	echo "  sudo reboot"
}

rollback_overlay() {
	require_root_or_print "$REPO_ROOT/scripts/snd-repair" rollback || return 1

	if [[ -d "$SND_REPAIR_OVERLAY_DIR" ]]; then
		echo "==> Removing $SND_REPAIR_OVERLAY_DIR"
		rm -rf "$SND_REPAIR_OVERLAY_DIR"
	else
		echo "==> No overlay at $SND_REPAIR_OVERLAY_DIR"
	fi
	rm -f "$SND_REPAIR_STATE_DIR/$KVER.state"
	# Remove depmod snippet only if no other ABI overlays remain
	if [[ -f "$SND_REPAIR_DEPMOD_CONF" ]] && ! compgen -G "/lib/modules/*/updates/snd_repair" >/dev/null 2>&1; then
		rm -f "$SND_REPAIR_DEPMOD_CONF"
		echo "==> Removed $SND_REPAIR_DEPMOD_CONF"
	fi
	depmod -a "$KVER"
	echo "Rollback done for $KVER. Reboot to reload stock modules:"
	echo "  sudo reboot"
	if intree_has_legacy_patches; then
		echo ""
		echo "NOTE: in-tree modules still carry snd_repair markers (legacy overwrite)."
		echo "Restore stock with:"
		echo "  sudo apt-get install --reinstall linux-modules-$KVER"
	fi
}

intree_has_legacy_patches() {
	ko_strings_has "$INTREE_TAS" "$MARKER_0001" || ko_strings_has "$INTREE_AMD" "$MARKER_0002"
}

px13_resume_enabled() {
	systemctl is-enabled px13-audio-resume.service >/dev/null 2>&1
}

grub_var() {
	local key="$1"
	local f=/etc/default/grub
	[[ -r "$f" ]] || return 1
	grep -E "^${key}=" "$f" | tail -1 | cut -d= -f2- | tr -d '"'
}

count_linux_images() {
	compgen -G '/boot/vmlinuz-*' | wc -l
}

preflight_install() {
	local err=0
	if px13_resume_enabled; then
		echo "ERROR: px13-audio-resume.service is enabled — conflicts with kernel patches." >&2
		echo "  sudo systemctl disable --now px13-audio-resume.service" >&2
		err=1
	fi
	local timeout style
	timeout="$(grub_var GRUB_TIMEOUT 2>/dev/null || echo '?')"
	style="$(grub_var GRUB_TIMEOUT_STYLE 2>/dev/null || echo '?')"
	if [[ "$timeout" == "0" ]] || [[ "$style" == "hidden" ]]; then
		echo "WARN: GRUB escape hatch weak (TIMEOUT=$timeout STYLE=$style)." >&2
		echo "  Apply gate first: sudo $REPO_ROOT/scripts/snd-repair gate" >&2
		# warn only — do not hard-fail (user may know)
	fi
	local n
	n="$(count_linux_images)"
	if [[ "$n" -lt 2 ]]; then
		echo "WARN: only $n kernel image(s) in /boot — keep previous ABI until smoke passes." >&2
	fi
	[[ -d "$KERNEL_BUILD" ]] || {
		echo "ERROR: missing headers: sudo apt install linux-headers-$KVER" >&2
		err=1
	}
	return "$err"
}
