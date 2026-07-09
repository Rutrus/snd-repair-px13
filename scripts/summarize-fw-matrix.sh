#!/bin/bash
# Resume tas2783-fw-matrix.log (un boot_id = una fila)
LOG="${1:-${HOME}/tas2783-fw-matrix.log}"

if [[ ! -f "$LOG" ]]; then
	echo "No existe: $LOG" >&2
	exit 1
fi

printf "%-4s %-12s %-12s %-12s %s\n" "Boot" ":8 (Left)" ":b (Right)" "Audio" "Fecha"
printf "%-4s %-12s %-12s %-12s %s\n" "----" "------------" "------------" "------------" "----------"

n=0
declare -A seen
boot_id=""
date=""
s8=""
sb=""
audio=""

while IFS= read -r line; do
	case "$line" in
	"====="*)
		[[ -n "$boot_id" && -z "${seen[$boot_id]:-}" ]] && {
			seen[$boot_id]=1
			n=$((n + 1))
			printf "%-4d %-12s %-12s %-12s %s\n" "$n" "$s8" "$sb" "$audio" "$date"
		}
		boot_id="$(echo "$line" | sed -n 's/.*boot_id=\([^ ]*\).*/\1/p' | cut -c1-8)"
		date="$(echo "$line" | sed -n 's/^===== \([^ ]*\).*/\1/p')"
		s8=""; sb=""; audio=""
		;;
	"  :8"*)
		s8="$(echo "$line" | awk -F= '{print $2}' | tr -d ' ')"
		;;
	"  :b"*)
		sb="$(echo "$line" | awk -F= '{print $2}' | tr -d ' ')"
		;;
	"  AUDIO:"*)
		audio="$(echo "$line" | sed 's/.*AUDIO: //')"
		;;
	esac
done < "$LOG"

[[ -n "$boot_id" && -z "${seen[$boot_id]:-}" ]] && {
	n=$((n + 1))
	printf "%-4d %-12s %-12s %-12s %s\n" "$n" "$s8" "$sb" "$audio" "$date"
}

echo ""
b_fail=$(grep -c 'FAIL(fw)' "$LOG" || true)
echo "Entradas :b FAIL(fw): $b_fail (puede incluir duplicados)"
echo "Leyenda: OK | FAIL(fw) | WARN(no-fw-hw_params)"
