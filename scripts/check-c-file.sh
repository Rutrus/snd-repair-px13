#!/usr/bin/env bash
# Static checks for kernel/driver C files (syntax, cppcheck, clang --analyze).
#
# Usage:
#   ./scripts/check-c-file.sh drivers/soundwire/amd_manager.c
#   ./scripts/check-c-file.sh --quick drivers/soundwire/amd_manager.c   # skip slow analyzers
#   ./scripts/check-c-file.sh --module drivers/soundwire amd_manager.c
#
# Requires (optional, uses what is installed):
#   cppcheck, clang, gcc + kernel headers (uname -r)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="${KERNEL_SRC:?KERNEL_SRC not set}"
BUILD="${KERNEL_BUILD:?KERNEL_BUILD not set}"
QUICK=0
MODULE_DIR=""
FILE=""

usage() {
	cat <<EOF
Usage:
  $0 [--quick] PATH/to/file.c
  $0 [--quick] --module drivers/soundwire file.c

Runs, when tools are available:
  1. snd-repair completeness heuristics (instrumentation call sites)
  2. gcc -fsyntax-only (single translation unit, kernel includes)
  3. cppcheck --enable=all --inconclusive
  4. clang --analyze

Install (Debian/Ubuntu):
  sudo apt install cppcheck clang clang-tidy
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--quick) QUICK=1; shift ;;
	--module) MODULE_DIR="${2:?}"; FILE="${3:?}"; shift 3 ;;
	-h|--help) usage; exit 0 ;;
	-*)
		echo "Unknown option: $1" >&2
		usage
		exit 1
		;;
	*)
		FILE="$1"
		shift
		;;
	esac
done

[[ -n "$FILE" ]] || { usage; exit 1; }

if [[ "$FILE" != /* ]]; then
	if [[ -n "$MODULE_DIR" ]]; then
		FILE="$SRC/$MODULE_DIR/$FILE"
	else
		FILE="$SRC/$FILE"
	fi
fi
[[ -f "$FILE" ]] || { echo "ERROR: not a file: $FILE" >&2; exit 1; }

REL="${FILE#"$SRC/"}"
MOD_DIR="$(dirname "$REL")"
BASENAME="$(basename "$FILE")"
FAIL=0

echo "==> check-c-file: $REL"

# --- snd-repair completeness (catches partial patches / dead instrumentation) ---
check_snd_repair_completeness() {
	local f="$1"
	local fn
	local missing=0

	while IFS= read -r fn; do
		[[ -n "$fn" ]] || continue
		local count
		count="$(grep -cE "${fn}[[:space:]]*\\(" "$f" 2>/dev/null || true)"
		count="${count:-0}"
		if [[ "$count" -le 1 ]]; then
			echo "ERROR: static helper '${fn}' is defined but has no call site in $REL" >&2
			missing=1
		fi
	done < <(grep -oE 'static[[:space:]]+(void|int|bool|u32|unsigned)[[:space:]]+snd_repair_[a-zA-Z0-9_]+' "$f" \
		| awk '{print $NF}' | sort -u)

	if grep -q 'SND_REPAIR_' "$f" && ! grep -q 'fn=intr_decode\|fn=delay_after_D0\|PHASE[67]' "$f"; then
		echo "WARN: SND_REPAIR_* macros present but no PHASE6/7 trace markers in $REL" >&2
	fi

	return "$missing"
}

kernel_include_args() {
	local args=(
		"-I$BUILD/include"
		"-I$BUILD/arch/x86/include"
		"-I$BUILD/arch/x86/include/generated"
		"-I$SRC/include"
		"-I$SRC/arch/x86/include"
		"-I$SRC/arch/x86/include/generated"
		"-include" "$BUILD/include/generated/autoconf.h"
		"-include" "$BUILD/include/linux/kconfig.h"
		"-D__KERNEL__"
		"-DMODULE"
		"-Wno-pragma-once-outside-header"
		"-Wno-unknown-warning-option"
	)
	printf '%s\n' "${args[@]}"
}

run_gcc_syntax() {
	if ! command -v gcc >/dev/null 2>&1; then
		echo "SKIP: gcc not found"
		return 0
	fi
	if [[ ! -d "$BUILD/include" ]]; then
		echo "SKIP: kernel build headers missing at $BUILD"
		return 0
	fi

	echo "==> gcc -fsyntax-only"
	local -a inc
	mapfile -t inc < <(kernel_include_args)
	# shellcheck disable=SC2068
	if gcc -fsyntax-only -std=gnu11 -Wall -Wextra "${inc[@]}" -c "$FILE" 2>&1; then
		echo "OK: gcc syntax"
	else
		echo "FAIL: gcc syntax" >&2
		return 1
	fi
}

run_cppcheck() {
	if ! command -v cppcheck >/dev/null 2>&1; then
		echo "SKIP: cppcheck not installed (sudo apt install cppcheck)"
		return 0
	fi

	echo "==> cppcheck --enable=all --inconclusive"
	local -a inc
	mapfile -t inc < <(kernel_include_args)
	local -a inc_flags=()
	local i
	for i in "${inc[@]}"; do
		case "$i" in
		-I*|-D*) inc_flags+=("$i") ;;
		esac
	done

	if cppcheck --quiet --error-exitcode=1 \
		--enable=all --inconclusive \
		--inline-suppr \
		--suppress=missingIncludeSystem \
		--suppress=unmatchedSuppression \
		"${inc_flags[@]}" \
		"$FILE" 2>&1; then
		echo "OK: cppcheck"
	else
		echo "FAIL: cppcheck" >&2
		return 1
	fi
}

run_clang_analyze() {
	if ! command -v clang >/dev/null 2>&1; then
		echo "SKIP: clang not installed (sudo apt install clang)"
		return 0
	fi
	if [[ ! -d "$BUILD/include" ]]; then
		echo "SKIP: kernel build headers missing at $BUILD"
		return 0
	fi

	echo "==> clang --analyze"
	local -a inc
	mapfile -t inc < <(kernel_include_args)
	# shellcheck disable=SC2068
	if clang --analyze -Xanalyzer -analyzer-output=text \
		-std=gnu11 -Wno-unknown-warning-option "${inc[@]}" -c "$FILE" 2>&1; then
		echo "OK: clang --analyze"
	else
		echo "FAIL: clang --analyze" >&2
		return 1
	fi
}

run_module_compile() {
	if ! command -v make >/dev/null 2>&1; then
		echo "SKIP: make not found"
		return 0
	fi
	echo "==> make module compile ($MOD_DIR)"
	if make -C "$BUILD" M="$SRC/$MOD_DIR" "obj-m:=$BASENAME.o" modules 2>&1 | tail -20; then
		echo "OK: module compile"
	else
		echo "FAIL: module compile (see make output above)" >&2
		return 1
	fi
}

check_snd_repair_completeness "$FILE" || FAIL=1

if [[ "$QUICK" -eq 0 ]]; then
	run_gcc_syntax || FAIL=1
	run_cppcheck || FAIL=1
	run_clang_analyze || FAIL=1
else
	echo "==> --quick: skipping gcc/cppcheck/clang"
fi

# Optional full module build (heavier but catches link-level issues)
if [[ "${CHECK_C_MODULE_BUILD:-0}" == 1 ]]; then
	run_module_compile || FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
	echo ""
	echo "Static check FAILED for $REL" >&2
	exit 1
fi

echo ""
echo "Static check passed for $REL"
