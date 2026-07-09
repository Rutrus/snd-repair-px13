#!/usr/bin/env bash
# Registra un boot en validation/fw-matrix.csv y archiva dmesg filtrado.
# Ejecutar una vez tras cada arranque (o tras suspend/resume / prueba de rate).
#
# Uso:
#   ~/snd_repair/scripts/fw-validation-collect.sh              # solo kernel/FW
#   ~/snd_repair/scripts/fw-validation-collect.sh --audio      # + speaker-test + preguntas
#   ~/snd_repair/scripts/fw-validation-collect.sh --rate 44100
#   ~/snd_repair/scripts/fw-validation-collect.sh --suspend
#   ~/snd_repair/scripts/fw-validation-collect.sh --notes "0006+0007"
#
# Variables:
#   VAL_DIR=~/snd_repair/validation
#   ALSA_DEV=plughw:1,2

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VAL_DIR="${VAL_DIR:-${REPO}/validation}"
CSV="${VAL_DIR}/fw-matrix.csv"
BOOT_LOGS="${VAL_DIR}/boot-logs"
ALSA_DEV="${ALSA_DEV:-plughw:1,2}"

DO_AUDIO=0
SUSPEND_RESUME="boot"
RATE=""
NOTES=""

usage() {
	sed -n '3,12p' "$0"
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--audio)    DO_AUDIO=1; shift ;;
	--suspend)  SUSPEND_RESUME="suspend_resume"; shift ;;
	--rate)     RATE="${2:?--rate requiere valor}"; shift 2 ;;
	--notes)    NOTES="${2:?--notes requiere texto}"; shift 2 ;;
	-h|--help)  usage ;;
	*)          echo "Opción desconocida: $1" >&2; usage ;;
	esac
done

mkdir -p "$BOOT_LOGS"

if command -v journalctl >/dev/null 2>&1; then
	KMLOG="$(journalctl -k -b 0 --no-pager 2>/dev/null || true)"
else
	KMLOG="$(dmesg -T 2>/dev/null || dmesg 2>/dev/null || true)"
fi

KERNEL="$(uname -r)"
CMDLINE="$(tr '\0' ' ' < /proc/cmdline 2>/dev/null || true)"
TIMESTAMP="$(date -Is)"
PROC_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"

# boot_id secuencial en CSV (reproducible entre sesiones)
if [[ -f "$CSV" ]]; then
	BOOT_ID=$(awk -F, 'NR>1 {print $1+0}' "$CSV" | sort -n | tail -1)
	BOOT_ID=$((BOOT_ID + 1))
else
	BOOT_ID=1
fi

BOOT_LOG=$(printf '%s/boot-%03d.log' "$BOOT_LOGS" "$BOOT_ID")

# --- Análisis FW por UID ---
uid_fw_status() {
	local uid="$1"
	local fail warn err

	fail=$(printf '%s\n' "$KMLOG" | grep -E "0102:0000:01:${uid}.*FW download failed" | wc -l)
	warn=$(printf '%s\n' "$KMLOG" | grep -E "0102:0000:01:${uid}.*playback without fw" | wc -l)

	if [[ "$fail" -gt 0 ]]; then
		err=$(printf '%s\n' "$KMLOG" | grep -E "0102:0000:01:${uid}.*FW download failed" |
			sed -n 's/.*FW download failed: \(-[0-9]*\).*/\1/p' | head -1)
		[[ -z "$err" ]] && err="-?"
		echo "FAIL${err#-}"
	elif [[ "$warn" -gt 0 ]]; then
		echo "WARN"
	else
		echo "OK"
	fi
}

uid_warn_count() {
	local uid="$1"
	printf '%s\n' "$KMLOG" | grep -cE "0102:0000:01:${uid}.*playback without fw" || true
}

UID8_FW="$(uid_fw_status 8)"
UIDB_FW="$(uid_fw_status b)"
UID8_WARN="$(uid_warn_count 8)"
UIDB_WARN="$(uid_warn_count b)"

# --- Regresión Problema A (capture en codec / transporte) ---
# Nota: SDW1-PIN4-CAPTURE prepare -22 puede persistir a nivel máquina;
# no cuenta como regresión de Serie A (ver capture_dailink_warn en log).
REGRESSION="NO"
CAPTURE_DAILINK_WARN="NO"
if grep -qF "Program transport params failed" <<<"$KMLOG"; then
	REGRESSION="YES"
fi
if grep -qiE 'tas2783.*Unable to configure port' <<<"$KMLOG"; then
	REGRESSION="YES"
fi
if grep -qE 'SDW1-PIN4-CAPTURE.*prepare ret=-22' <<<"$KMLOG"; then
	CAPTURE_DAILINK_WARN="YES"
fi

# --- Audio opcional ---
LEFT_AUDIO=""
RIGHT_AUDIO=""

if [[ "$DO_AUDIO" -eq 1 ]]; then
	if command -v speaker-test >/dev/null 2>&1; then
		echo ">>> Prueba L (speaker 1) — ${ALSA_DEV}"
		speaker-test -D "$ALSA_DEV" -c 2 -t wav -l 1 -s 1 2>/dev/null || true
		read -r -p "¿Canal izquierdo sonó? [y/N] " ans
		[[ "$ans" =~ ^[yY] ]] && LEFT_AUDIO=1 || LEFT_AUDIO=0

		echo ">>> Prueba R (speaker 2)"
		speaker-test -D "$ALSA_DEV" -c 2 -t wav -l 1 -s 2 2>/dev/null || true
		read -r -p "¿Canal derecho sonó? [y/N] " ans
		[[ "$ans" =~ ^[yY] ]] && RIGHT_AUDIO=1 || RIGHT_AUDIO=0
	else
		echo "speaker-test no instalado; audio omitido" >&2
	fi
fi

[[ -z "$RATE" ]] && RATE="48000"

# Escapar CSV (notas con comas)
csv_escape() {
	local s="$1"
	if [[ "$s" == *","* || "$s" == *"\""* ]]; then
		printf '"%s"' "${s//\"/\"\"}"
	else
		printf '%s' "$s"
	fi
}

# --- Archivar log ---
{
	echo "# boot_id=${BOOT_ID} timestamp=${TIMESTAMP} kernel=${KERNEL}"
	echo "# proc_boot_id=${PROC_BOOT_ID}"
	echo "# cmdline=${CMDLINE}"
	echo "# uid8_fw=${UID8_FW} uidb_fw=${UIDB_FW} regression_capture=${REGRESSION} capture_dailink_warn=${CAPTURE_DAILINK_WARN}"
	echo "# --- filtered tas2783 / FW ---"
	grep -iE \
		'FW download failed|playback without fw|tas2783|0102:0000:01:(8|b)|-110|ENZOFW|ENZOPLAY.*ch_mask|SDW1-PIN4-CAPTURE|Program transport params failed|dpn_prop|Prepare port' \
		<<<"$KMLOG" || true
	echo "# --- full kernel log ---"
	printf '%s\n' "$KMLOG"
} >"$BOOT_LOG"

# --- CSV ---
if [[ ! -f "$CSV" ]]; then
	echo "boot_id,timestamp,kernel,uid8_fw,uidb_fw,uid8_warn,uidb_warn,left_audio,right_audio,suspend_resume,rate,regression_capture,notes" >"$CSV"
fi

{
	printf '%s,' "$BOOT_ID"
	printf '%s,' "$TIMESTAMP"
	printf '%s,' "$KERNEL"
	printf '%s,' "$UID8_FW"
	printf '%s,' "$UIDB_FW"
	printf '%s,' "$UID8_WARN"
	printf '%s,' "$UIDB_WARN"
	printf '%s,' "$LEFT_AUDIO"
	printf '%s,' "$RIGHT_AUDIO"
	printf '%s,' "$SUSPEND_RESUME"
	printf '%s,' "$RATE"
	printf '%s,' "$REGRESSION"
	printf '%s\n' "$(csv_escape "$NOTES")"
} >>"$CSV"

echo "Registrado boot #${BOOT_ID} → ${CSV}"
echo "Log completo → ${BOOT_LOG}"
echo "  :8=${UID8_FW}  :b=${UIDB_FW}  regression_capture=${REGRESSION}  capture_dailink_warn=${CAPTURE_DAILINK_WARN}"

# Actualizar resumen
"$(dirname "$0")/fw-validation-summarize.sh" "$VAL_DIR"
