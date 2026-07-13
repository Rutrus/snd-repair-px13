#!/usr/bin/env bash
# W4c — diff normalized W4b write traces (PASS vs FAIL).
#
# Usage:
#   ./scripts/w4-write-trace-diff.sh validation/w4b-write-pass-* validation/w4b-write-fail-s2-*
#   ./scripts/w4-write-trace-diff.sh --uid 8 pass-dir fail-dir
set -euo pipefail
export LC_ALL=C

UID_FILTER=""
PASS_DIR=""
FAIL_DIR=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--uid) UID_FILTER="$2"; shift 2 ;;
	-h|--help) sed -n '3,8p' "$0"; exit 0 ;;
	-*)
		echo "Unknown: $1" >&2
		exit 1
		;;
	*)
		if [[ -z "$PASS_DIR" ]]; then PASS_DIR="$1"
		elif [[ -z "$FAIL_DIR" ]]; then FAIL_DIR="$1"
		else echo "Too many dirs" >&2; exit 1
		fi
		shift
		;;
	esac
done

[[ -n "$PASS_DIR" && -n "$FAIL_DIR" ]] || {
	echo "Usage: $0 [--uid 8|11] <pass-dir> <fail-dir>" >&2
	exit 1
}

pick_file() {
	local dir="$1" base="$2"
	if [[ -f "$dir/w4b-window-norm.txt" ]]; then echo "$dir/w4b-window-norm.txt"
	elif [[ -f "$dir/w4b-write-norm.txt" ]]; then echo "$dir/w4b-write-norm.txt"
	else echo "$dir/$base" >&2; return 1
	fi
}

PASS_FILE="$(pick_file "$PASS_DIR" w4b-write-norm.txt)"
FAIL_FILE="$(pick_file "$FAIL_DIR" w4b-write-norm.txt)"

filter_uid() {
	local f="$1"
	if [[ -z "$UID_FILTER" ]]; then cat "$f"
	else awk -v u="$UID_FILTER" '$1 == u {print}' "$f"
	fi
}

PASS_NORM="$(mktemp)"
FAIL_NORM="$(mktemp)"
trap 'rm -f "$PASS_NORM" "$FAIL_NORM"' EXIT

filter_uid "$PASS_FILE" >"$PASS_NORM"
filter_uid "$FAIL_FILE" >"$FAIL_NORM"

echo "=== W4c write trace — lines only in PASS ==="
comm -23 <(sort "$PASS_NORM") <(sort "$FAIL_NORM") | head -40
echo "... ($(comm -23 <(sort "$PASS_NORM") <(sort "$FAIL_NORM") | wc -l) total)"

echo
echo "=== W4c write trace — lines only in FAIL ==="
comm -13 <(sort "$PASS_NORM") <(sort "$FAIL_NORM") | head -40
echo "... ($(comm -13 <(sort "$PASS_NORM") <(sort "$FAIL_NORM") | wc -l) total)"

echo
echo "=== W4c — same reg:val, different phase/fn (ordered diff) ==="
# Compare reg:val sequence ignoring uid
cut -d' ' -f2- "$PASS_NORM" | awk '{print $1" "$4" "$5}' >"${PASS_NORM}.rv"
cut -d' ' -f2- "$FAIL_NORM" | awk '{print $1" "$4" "$5}' >"${FAIL_NORM}.rv"
diff -u "${PASS_NORM}.rv" "${FAIL_NORM}.rv" | head -60 || true

echo
echo "=== First positional mismatch (phase reg val) ==="
python3 - <<PY
pass_lines = open("$PASS_NORM").read().splitlines()
fail_lines = open("$FAIL_NORM").read().splitlines()
for i, (p, f) in enumerate(zip(pass_lines, fail_lines)):
    if p != f:
        print(f"index {i}:")
        print(f"  PASS: {p}")
        print(f"  FAIL: {f}")
        break
else:
    if len(pass_lines) != len(fail_lines):
        print(f"length PASS={len(pass_lines)} FAIL={len(fail_lines)}")
        shorter = min(len(pass_lines), len(fail_lines))
        print(f"first extra after index {shorter}:")
        if len(pass_lines) > shorter:
            print("  PASS only:", pass_lines[shorter])
        if len(fail_lines) > shorter:
            print("  FAIL only:", fail_lines[shorter])
    else:
        print("identical normalized write sequences")
PY
