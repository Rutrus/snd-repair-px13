#!/usr/bin/env bash
# 2×2 matrix: ALSA access mode × buffer geometry (post-S2, PW stopped).
#
# Usage:
#   ./scripts/post-s2-capture-access-matrix.sh
#   ./scripts/post-s2-capture-access-matrix.sh --device hw:1,1 --format S16_LE
#
# Env:
#   MATRIX_RECORD_SEC=2
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ALSA_DEV="${MATRIX_ALSA_DEV:-hw:1,4}"
FMT="${MATRIX_FORMAT:-S32_LE}"
RECORD_SEC="${MATRIX_RECORD_SEC:-2}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--device) ALSA_DEV="$2"; shift 2 ;;
	--format) FMT="$2"; shift 2 ;;
	--out-dir) OUT_DIR="$2"; shift 2 ;;
	-h|--help)
		sed -n '3,12p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS_FILE="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-${REPO}/validation/capture-access-matrix-${TS_FILE}}"
mkdir -p "$OUT_DIR"

exec > >(tee "${OUT_DIR}/matrix.log") 2>&1

echo "=== CAPTURE ACCESS × GEOMETRY MATRIX ==="
echo "time=$(date -Iseconds) device=$ALSA_DEV format=$FMT sec=$RECORD_SEC"
echo "output_dir=$OUT_DIR"
echo

if ! command -v arecord >/dev/null; then
	echo "FAIL: arecord missing"; exit 1
fi

echo "--- stopping PipeWire ---"
systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
sleep 2

_run() {
	local id="$1" access="$2" geom="$3"
	shift 3
	local wav="${OUT_DIR}/${id}.wav"
	local log="${OUT_DIR}/${id}.log"
	local extra=("$@")
	local rc=0 size=0 verdict=FAIL

	echo "--- $id: access=$access geometry=$geom ---"
	if arecord -D "$ALSA_DEV" -f "$FMT" -r 48000 -c 2 -d "$RECORD_SEC" \
		"${extra[@]}" "$wav" >"$log" 2>&1; then
		rc=0
	else
		rc=1
	fi
	size="$(stat -c%s "$wav" 2>/dev/null || echo 0)"
	# WAV header alone ≈ 44 B → functional fail
	if [[ "$rc" -eq 0 && "$size" -gt 1000 ]]; then
		verdict=PASS
	fi
	echo "RESULT $id verdict=$verdict exit=$rc bytes=$size"
	tail -2 "$log" 2>/dev/null || true

	# snapshot hw_params if PCM still open
	local pcm="pcm4c"
	[[ "$ALSA_DEV" == *",1" ]] && pcm="pcm1c"
	if [[ -r "/proc/asound/card1/${pcm}/sub0/hw_params" ]]; then
		grep -v '^closed' "/proc/asound/card1/${pcm}/sub0/hw_params" 2>/dev/null \
			| tee "${OUT_DIR}/${id}-hw_params.txt" || true
	fi
	echo
	printf '%s\n' "$id|$access|$geom|$verdict|$size" >> "${OUT_DIR}/results.tsv"
}

: > "${OUT_DIR}/results.tsv"
echo -e "id\taccess\tgeometry\tverdict\tbytes" >> "${OUT_DIR}/results.tsv"

# large = arecord defaults (RW ~2048/16384; MMAP defaults when only -M)
_run rw-large    RW   "default (2048/16384 typ.)"
_run rw-small    RW   "1024/4096" --period-size=1024 --buffer-size=4096
_run mmap-large  MMAP "default" -M
_run mmap-small  MMAP "1024/4096" -M --period-size=1024 --buffer-size=4096

echo "--- restarting PipeWire ---"
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

{
	echo "Matrix summary ($ALSA_DEV $FMT)"
	echo "time=$(date -Iseconds)"
	echo
	printf '| Access | Geometry | Verdict | Bytes |\n'
	printf '|--------|----------|---------|-------|\n'
	tail -n +2 "${OUT_DIR}/results.tsv" | while IFS='|' read -r id access geom verdict bytes; do
		printf '| %s | %s | %s | %s |\n' "$access" "$geom" "$verdict" "$bytes"
	done
	echo
	echo "Interpretation:"
	grep -q 'rw-large|.*|FAIL' "${OUT_DIR}/results.tsv" 2>/dev/null || true
	passes="$(grep -c '|PASS|' "${OUT_DIR}/results.tsv" || true)"
	rw_pass="$(grep '^rw-' "${OUT_DIR}/results.tsv" | grep -c PASS || true)"
	mmap_pass="$(grep '^mmap-' "${OUT_DIR}/results.tsv" | grep -c PASS || true)"
	rw_small="$(grep '^rw-small|' "${OUT_DIR}/results.tsv" | cut -d'|' -f4)"
	mmap_large="$(grep '^mmap-large|' "${OUT_DIR}/results.tsv" | cut -d'|' -f4)"
	rw_large="$(grep '^rw-large|' "${OUT_DIR}/results.tsv" | cut -d'|' -f4)"
	mmap_small="$(grep '^mmap-small|' "${OUT_DIR}/results.tsv" | cut -d'|' -f4)"

	if [[ "$rw_large" == FAIL && "$mmap_small" == PASS && "$mmap_large" == PASS && "$rw_small" == FAIL ]]; then
		echo "→ ACCESS is the determinant (MMAP passes both geometries; RW fails both)."
	elif [[ "$rw_large" == FAIL && "$rw_small" == PASS ]]; then
		echo "→ GEOMETRY fixes RW (buffer size matters, not only MMAP)."
	elif [[ "$rw_large" == FAIL && "$mmap_large" == FAIL && "$mmap_small" == PASS ]]; then
		echo "→ Both ACCESS and GEOMETRY required (only mmap-small passes)."
	elif [[ "$rw_small" == PASS ]]; then
		echo "→ RW can work with small geometry (MMAP not strictly required)."
	else
		echo "→ See results.tsv — pattern inconclusive or mixed."
	fi
	echo "pass_count=$passes rw_pass=$rw_pass mmap_pass=$mmap_pass"
} | tee "${OUT_DIR}/summary.md"

echo
echo "matrix complete: $OUT_DIR"
