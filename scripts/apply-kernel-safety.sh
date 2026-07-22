#!/usr/bin/env bash
# Minimal GRUB escape hatch for snd_repair (menu + saved default).
# Does not hold packages or touch unattended-upgrades unless --full.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

GRUB_FILE=/etc/default/grub
FULL=0

usage() {
	cat <<EOF
Usage: sudo $0 [--full]

  Default: GRUB_TIMEOUT=5, TIMEOUT_STYLE=menu, DEFAULT=saved (+ SAVEDEFAULT)
  --full:  also blacklist linux-* in unattended-upgrades (if present)

Without root, prints the exact sudo command and a dry-run of intended edits.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--full) FULL=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
	shift
done

set_grub_kv() {
	local key="$1"
	local val="$2"
	local file="$3"
	if grep -qE "^#?${key}=" "$file"; then
		sed -i -E "s|^#?${key}=.*|${key}=${val}|" "$file"
	else
		printf '%s=%s\n' "$key" "$val" >>"$file"
	fi
}

print_plan() {
	echo "Planned GRUB changes ($GRUB_FILE):"
	echo "  GRUB_TIMEOUT=5"
	echo "  GRUB_TIMEOUT_STYLE=menu"
	echo "  GRUB_DEFAULT=saved"
	echo "  GRUB_SAVEDEFAULT=true"
	if [[ "$FULL" -eq 1 ]]; then
		echo "  + unattended-upgrades blacklist for linux-*"
	fi
	echo "Then: update-grub"
}

if [[ ! -w /etc/default ]] || [[ ! -w "$GRUB_FILE" ]]; then
	print_plan
	echo ""
	echo "Run:"
	if [[ "$FULL" -eq 1 ]]; then
		echo "  sudo $SCRIPT_DIR/apply-kernel-safety.sh --full"
	else
		echo "  sudo $SCRIPT_DIR/apply-kernel-safety.sh"
	fi
	exit 1
fi

[[ -f "$GRUB_FILE" ]] || {
	echo "Missing $GRUB_FILE" >&2
	exit 1
}

cp -a "$GRUB_FILE" "$GRUB_FILE.snd-repair.bak.$(date +%Y%m%d%H%M%S)"
echo "==> Backup: $GRUB_FILE.snd-repair.bak.*"

set_grub_kv GRUB_TIMEOUT 5 "$GRUB_FILE"
set_grub_kv GRUB_TIMEOUT_STYLE menu "$GRUB_FILE"
set_grub_kv GRUB_DEFAULT saved "$GRUB_FILE"
set_grub_kv GRUB_SAVEDEFAULT true "$GRUB_FILE"

if [[ "$FULL" -eq 1 ]]; then
	UA=/etc/apt/apt.conf.d/50unattended-upgrades
	DROP=/etc/apt/apt.conf.d/52snd-repair-kernel-blacklist
	if [[ -d /etc/apt/apt.conf.d ]]; then
		cat >"$DROP" <<'EOF'
// snd_repair — do not auto-install new linux images without rebuild/smoke
Unattended-Upgrade::Package-Blacklist {
    "linux-image-";
    "linux-headers-";
    "linux-modules-";
    "linux-modules-extra-";
};
EOF
		echo "==> Wrote $DROP"
	else
		echo "WARN: no apt.conf.d — skip unattended-upgrades blacklist"
	fi
	# Keep reference to stock file if present (no edit of 50unattended-upgrades)
	[[ -f "$UA" ]] || true
fi

n="$(compgen -G '/boot/vmlinuz-*' | wc -l)"
echo "==> Kernel images in /boot: $n"
if [[ "$n" -lt 2 ]]; then
	echo "WARN: keep ≥2 linux-image packages until the new ABI is smoke-tested"
fi

echo "==> update-grub"
update-grub

echo ""
echo "Gate applied. On next boot you get a ~5s GRUB menu; default is 'saved'."
echo "After a good smoke test on a new ABI:"
echo "  sudo grub-set-default 0   # or the menu entry index/title you want"
echo "Status:"
echo "  $SCRIPT_DIR/snd-repair status"
