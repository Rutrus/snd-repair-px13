#!/usr/bin/env bash
# W2 — build snd-soc-tas2783-sdw with upstream series B + force-fw-reinit hack.
#
# Usage:
#   sudo ./scripts/build-w2-force-fw.sh
#   sudo ./scripts/build-w2-force-fw.sh --trace   # also apply Q2 TAS2783Q2 probes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
W2_PATCH="$REPO_ROOT/research/make-it-work/patches/w2-force-fw-reinit.patch"
W2_STAMP="$SRC/.snd-repair-w2-force-fw-applied"
Q2_PATCH="$REPO_ROOT/research/q2-fw-resume/patches/0001-tas2783-q2-resume-trace.patch"
Q2_STAMP="$SRC/.snd-repair-q2-fw-trace-applied"
WITH_TRACE=0
SKIP_INSTALL=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--trace) WITH_TRACE=1; shift ;;
	--skip-install) SKIP_INSTALL=1; shift ;;
	-h|--help)
		echo "Usage: $0 [--trace] [--skip-install]"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

if [[ ! -f "$SRC/Makefile" ]]; then
	echo "Run first: $SCRIPT_DIR/prepare-kernel-tree.sh" >&2
	exit 1
fi

if [[ -f "$SRC/.snd-repair-production-applied" ]]; then
	echo "Production patches on tree — reset: $SCRIPT_DIR/reset-kernel-tree.sh" >&2
	exit 1
fi

if [[ ! -f "$SRC/.snd-repair-upstream-applied" ]]; then
	"$SCRIPT_DIR/apply-upstream-patches.sh"
fi

cd "$SRC"

CODEC_DIR="$SRC/sound/soc/codecs"
C_SRC="$CODEC_DIR/tas2783-sdw.c"

if ! rg -q 'tas2783_fw_reinit' "$C_SRC"; then
	echo "ERROR: series B 0003 not on tree — run apply-upstream-patches.sh" >&2
	exit 1
fi

apply_w2() {
	if [[ -f "$W2_STAMP" ]] && grep -Fq 'W2 ctx=tas fn=force_fw_reinit' "$C_SRC"; then
		echo "==> W2 force-fw patch already applied ($(cat "$W2_STAMP"))"
		return 0
	fi
	[[ -f "$W2_STAMP" ]] && rm -f "$W2_STAMP"
	echo "==> Applying W2 force-fw-reinit patch"
	if patch -p1 --forward <"$W2_PATCH"; then
		date -Is >"$W2_STAMP"
	elif patch -p1 --reverse --dry-run <"$W2_PATCH" >/dev/null 2>&1; then
		echo "    W2 patch already present"
		date -Is >"$W2_STAMP"
	else
		echo "Failed to apply $W2_PATCH" >&2
		exit 1
	fi
}

apply_q2_trace() {
	if [[ -f "$Q2_STAMP" ]] && grep -Fq 'TAS2783Q2 fn=' "$C_SRC"; then
		echo "==> Q2 trace already applied ($(cat "$Q2_STAMP"))"
		return 0
	fi
	[[ -f "$Q2_STAMP" ]] && rm -f "$Q2_STAMP"
	echo "==> Applying Q2 TAS2783Q2 trace (optional)"
	if patch -p1 --forward <"$Q2_PATCH"; then
		date -Is >"$Q2_STAMP"
	elif patch -p1 --reverse --dry-run <"$Q2_PATCH" >/dev/null 2>&1; then
		date -Is >"$Q2_STAMP"
	else
		echo "Failed to apply $Q2_PATCH" >&2
		echo "Regenerate: $SCRIPT_DIR/regenerate-q2-fw-trace-patch.sh" >&2
		exit 1
	fi
}

apply_w2
[[ "$WITH_TRACE" -eq 1 ]] && apply_q2_trace

if [[ ! -d "$BUILD" ]]; then
	echo "Missing headers: sudo apt install linux-headers-$KVER" >&2
	exit 1
fi

KO="$CODEC_DIR/snd-soc-tas2783-sdw.ko"
name="snd-soc-tas2783-sdw.ko"
dest="/lib/modules/$KVER/kernel/sound/soc/codecs/${name}.zst"
backup="$HOME/${name}.zst.orig"

if ! grep -Fq 'W2 ctx=tas fn=force_fw_reinit' "$C_SRC"; then
	echo "ERROR: W2 patch not in $C_SRC — remove $W2_STAMP and re-run" >&2
	exit 1
fi

echo "==> Building snd-soc-tas2783-sdw (upstream B + W2)"
rm -f "$CODEC_DIR"/tas2783-sdw.o "$CODEC_DIR"/snd-soc-tas2783-sdw.o \
	"$CODEC_DIR"/snd-soc-tas2783-sdw.ko "$CODEC_DIR"/.tas2783-sdw.o.cmd \
	"$CODEC_DIR"/.snd-soc-tas2783-sdw.ko.cmd
make -C "$BUILD" M="$CODEC_DIR" CONFIG_SND_SOC_TAS2783_SDW=m modules

[[ -f "$KO" ]] || { echo "Missing $KO" >&2; exit 1; }

if grep -Fq 'W2 ctx=tas fn=force_fw_reinit' "$C_SRC" && \
   { ! grep -Fq 'TAS2783Q2 fn=' "$C_SRC" || \
     command strings -a "$KO" | command grep -Fq 'TAS2783Q2 fn='; }; then
	if grep -Fq 'TAS2783Q2 fn=' "$C_SRC"; then
		echo "OK: W2 + Q2 present in source"
	elif command strings -a "$KO" | command grep -Fq 'W2 ctx=tas fn=force_fw_reinit'; then
		echo "OK: W2 force_fw_reinit present (source + module)"
	else
		echo "OK: W2 present in source"
	fi
elif grep -Fq 'W2 ctx=tas fn=force_fw_reinit' "$C_SRC"; then
	echo "OK: W2 present in source"
else
	echo "ERROR: W2 patch missing after build" >&2
	exit 1
fi

if [[ "$WITH_TRACE" -eq 1 ]] && ! grep -Fq 'TAS2783Q2 fn=' "$C_SRC"; then
	echo "ERROR: --trace requested but TAS2783Q2 not in $C_SRC" >&2
	echo "  Remove $Q2_STAMP and re-run, or: $SCRIPT_DIR/regenerate-q2-fw-trace-patch.sh" >&2
	exit 1
fi

if [[ ! -f "$backup" && -f "$dest" ]]; then
	echo "==> Backup: $backup"
	sudo cp "$dest" "$backup"
fi

if [[ "$SKIP_INSTALL" -eq 1 ]]; then
	echo "==> W2 build OK (install skipped — caller will install W2+W3)"
else
	zstd -19 -f "$KO" -o "/tmp/$name.zst"
	echo "==> Installing $dest"
	sudo cp "/tmp/$name.zst" "$dest"
	sudo depmod -a
	echo ""
	echo "==> W2 codec module installed for $KVER"
	echo ""
	echo "Reboot (or reload stack), then after S2:"
	echo "  journalctl -k -b 0 | grep -E 'W2 ctx=tas|fw_ready|hw_params'"
	echo "  speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1"
fi
